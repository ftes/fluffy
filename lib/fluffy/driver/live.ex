defmodule Fluffy.Driver.Live do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  import Phoenix.LiveViewTest, except: [open_browser: 1, open_browser: 2]

  alias Fluffy.Backend.Phoenix.HTTP
  alias Fluffy.ClientDOM
  alias Fluffy.Deadline
  alias Fluffy.Driver.Live.ActionResolver
  alias Fluffy.Driver.Live.ActionScope
  alias Fluffy.Driver.Live.Click
  alias Fluffy.Driver.Live.Document
  alias Fluffy.Driver.Live.Event
  alias Fluffy.Driver.Live.Retry
  alias Fluffy.Driver.Live.UploadState
  alias Fluffy.Expect
  alias Fluffy.Form
  alias Fluffy.HTML.DocumentIndex
  alias Fluffy.Internal.Navigation
  alias Fluffy.Internal.Navigation.Redirect
  alias Fluffy.LiveViewTest.UploadCompat
  alias Fluffy.Locator
  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.URLMatcher

  @retry_interval 10

  @impl true
  def open_browser(%Session{} = session, open_fun) do
    endpoint = Session.context(session).http.endpoint
    Fluffy.OpenBrowser.write(document(session), Fluffy.OpenBrowser.static_asset_resolver(endpoint), open_fun)
    session
  end

  @impl true
  def validate_operation!(session, operation, arguments),
    do: Fluffy.Driver.PhoenixValidation.validate_operation!(session, operation, arguments)

  @impl true
  def expect(%Session{} = session, %Expect{} = expectation) do
    deadline = Retry.deadline(session, Keyword.validate!(expectation.options, [:timeout]))

    result =
      eventually(session, deadline, fn session ->
        case evaluate_expectation(session, expectation) do
          {:ok, passed?, _actual} when passed? != expectation.negated? ->
            {:ok, session}

          {:ok, _passed?, actual} ->
            {:retry, "Expected #{Expect.Internal.describe(expectation)}, got #{inspect(actual)}"}
        end
      end)

    # An expectation goes on on the page a navigation landed on, like an
    # action, so pages that keep navigating fail it at the redirect limit.
    case result do
      {:navigate, session, navigation, {:retry, _remaining}} ->
        {session, redirects} = follow_for_retry(session, navigation)
        retry_on_new_page(session, redirects, :expect, [expectation], deadline)

      session ->
        session
    end
  end

  @impl true
  def click(%Session{} = session, %Locator{} = locator, action_options \\ []) do
    act(session, :click, [locator, action_options], fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &ClientDOM.click(&1, locator)) do
        {%Session{} = session, {client_dom, target}} -> commit_click(session, client_dom, target)
        navigation -> navigation
      end
    end)
  end

  defp commit_click(session, client_dom, target) do
    state = Session.page_state(session)

    with {:ok, event_context} <- owning_view_context(session, target) do
      case ClientDOM.phoenix_html_submission(client_dom, target) do
        submission when is_map(submission) ->
          if competing_live_click_binding?(target) do
            raise Fluffy.CapabilityError,
              capability: :phoenix_html_live_action_conflict,
              driver: :live,
              detail:
                "a data-method/data-to link with a competing phx-click or LiveView navigation action requires Playwright"
          else
            {:navigate, Session.put_page_state(session, %{state | client_dom: client_dom}),
             Navigation.submission(submission)}
          end

        nil ->
          commit_plain_click(session, client_dom, target, event_context)
      end
    end
  end

  defp competing_live_click_binding?(target) do
    Enum.any?([target | Enum.reverse(target.ancestors)], fn element ->
      not is_nil(attribute(element.attributes, "phx-click")) or
        not is_nil(attribute(element.attributes, "data-phx-link"))
    end)
  end

  defp commit_plain_click(session, client_dom, target, event_context) do
    state = Session.page_state(session)
    event_view = event_context.view

    case live_click_action(target) do
      :dispatch_change ->
        dispatch_live_click_change(session, client_dom, target, event_context)

      :render_click ->
        result =
          dispatch_view_event(session, fn ->
            Click.render(event_view, client_dom, target, view_selector(client_dom, target.selector, event_context))
          end)

        case commit_render_result(session, client_dom, result, event_view) do
          %Session{} = session -> release_cancelled_live_upload(session, target)
          navigation -> navigation
        end

      :none ->
        session = Session.put_page_state(session, %{state | client_dom: client_dom})

        case ClientDOM.form_submission(client_dom, target, :live) do
          %{phx_submit?: true} = submission ->
            case live_upload_for_submit(session, target) do
              {:ok, form_id, upload} ->
                dispatch_live_upload_submit(
                  session,
                  client_dom,
                  form_id,
                  upload,
                  submission,
                  event_context
                )

              :none ->
                dispatch_live_submit(session, client_dom, submission, event_context)
            end

          %{phx_submit?: false} = submission ->
            {:navigate, session, Navigation.submission(submission)}

          nil ->
            case {target.tag, attribute(target.attributes, "href")} do
              {tag, href} when tag in ["a", "area"] and is_binary(href) ->
                {:navigate, session,
                 Navigation.link(href,
                   download: attribute(target.attributes, "download")
                 )}

              _other ->
                session
            end
        end
    end
  end

  defp dispatch_live_click_change(session, client_dom, target, event_context) do
    state = Session.page_state(session)
    event_view = event_context.view
    session = Session.put_page_state(session, %{state | client_dom: client_dom})

    case ClientDOM.dispatch_change_event(client_dom, target) do
      nil ->
        session

      event ->
        payload =
          event.fields
          |> Form.to_params()
          |> Map.put("_target", event.target_name || "undefined")
          |> decode_merge_target()

        result =
          dispatch_view_event(session, fn ->
            render_view_event(client_dom, event_context, event.dispatcher_selector, :change, payload)
          end)

        commit_render_result(session, client_dom, result, event_view)
    end
  end

  @impl true
  def submit(%Session{} = session, %Locator{} = locator, options \\ []) do
    act(session, :submit, [locator, options], fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &ClientDOM.target!(&1, locator)) do
        {%Session{} = session, target} -> commit_submit(session, target)
        navigation -> navigation
      end
    end)
  end

  defp commit_submit(session, target) do
    client_dom = Session.page_state(session).client_dom

    with {:ok, event_context} <- owning_view_context(session, target) do
      case ClientDOM.submit_form(client_dom, target, :live) do
        nil ->
          raise ArgumentError, "submit/2 requires a form locator, got #{inspect(target.tag)}"

        %{phx_submit?: true} = submission ->
          dispatch_live_submit(session, client_dom, submission, event_context)

        %{phx_submit?: false} = submission ->
          {:navigate, session, Navigation.submission(submission)}
      end
    end
  end

  @impl true
  def fill(%Session{} = session, %Locator{} = locator, value, options \\ []) do
    act(session, :fill, [locator, value, options], fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &ClientDOM.fill(&1, locator, value, :live)) do
        {%Session{} = session, {client_dom, target}} -> dispatch_live_change(session, client_dom, target)
        navigation -> navigation
      end
    end)
  end

  @impl true
  def set_input_files(%Session{} = session, %Locator{} = locator, source_paths, selected_files, options \\ []) do
    act(session, :set_input_files, [locator, source_paths, selected_files, options], fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &select_files(&1, locator, selected_files)) do
        {%Session{} = session, :live_upload} ->
          set_live_upload(session, locator, selected_files)

        {%Session{} = session, %ClientDOM{} = client_dom} ->
          state = Session.page_state(session)
          Session.put_page_state(session, %{state | client_dom: client_dom})

        navigation ->
          navigation
      end
    end)
  end

  # Files selected in a LiveView-managed form upload through the view, while
  # any other input, or clearing one, only keeps the selection.
  defp select_files(client_dom, locator, selected_files) do
    if selected_files != [] and ClientDOM.live_managed_form?(client_dom, locator) do
      :live_upload
    else
      ClientDOM.set_input_files(client_dom, locator, selected_files)
    end
  end

  @doc false
  def release_page_uploads(%Session{} = session, %Page.State{driver: :live, state: state}) do
    state
    |> Map.fetch!(:live_uploads)
    |> UploadState.forms()
    |> Enum.each(&release_live_upload_clients(session, &1))

    :ok
  end

  def release_page_uploads(%Session{}, %Page.State{}), do: :ok

  @impl true
  def set_checked(%Session{} = session, %Locator{} = locator, desired, options \\ []) do
    act(session, :set_checked, [locator, desired, options], fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &ClientDOM.set_checked(&1, locator, desired)) do
        {%Session{} = session, {candidate_client_dom, target}} ->
          state = Session.page_state(session)

          if candidate_client_dom == state.client_dom do
            session
          else
            commit_checked(session, candidate_client_dom, target)
          end

        navigation ->
          navigation
      end
    end)
  end

  defp commit_checked(session, client_dom, target) do
    identity = Map.fetch!(ClientDOM.index(client_dom).nodes_by_id, target.id).identity

    case commit_click(session, client_dom, target) do
      %Session{} = session ->
        client_dom = Session.page_state(session).client_dom

        # A selector such as :checked stops matching after uncheck. Follow the
        # original control across any click patch instead of resolving it again,
        # and find the view that owns it there, since the click may have moved it.
        case Enum.find(ClientDOM.index(client_dom).entries, &(&1.identity == identity)) do
          nil ->
            session

          entry ->
            dispatch_live_change(session, client_dom, DocumentIndex.target_by_id(ClientDOM.index(client_dom), entry.id))
        end

      navigation ->
        navigation
    end
  end

  @impl true
  def select_option(%Session{} = session, %Locator{} = locator, requested, options \\ []) do
    act(session, :select_option, [locator, requested, options], fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &ClientDOM.select_option(&1, locator, requested)) do
        {%Session{} = session, {client_dom, target}} -> dispatch_live_change(session, client_dom, target)
        navigation -> navigation
      end
    end)
  end

  @impl true
  def press(%Session{} = session, %Locator{} = locator, key, options \\ []) do
    act(session, :press, [locator, key, options], fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &ClientDOM.target!(&1, locator)) do
        {%Session{} = session, target} -> dispatch_keys(session, locator, target, key, deadline)
        navigation -> navigation
      end
    end)
  end

  defp dispatch_keys(session, locator, target, key, deadline) do
    phases = Enum.filter([:keydown, :keyup], &key_binding?(target, &1))
    phases = if phases == [], do: [:keydown], else: phases

    Enum.reduce_while(phases, session, fn phase, session ->
      case dispatch_key(session, locator, key, phase, deadline) do
        %Session{} = session -> {:cont, session}
        navigation -> {:halt, navigation}
      end
    end)
  end

  defp key_binding?(target, phase) do
    attribute(target.attributes, "phx-#{phase}") != nil or
      attribute(target.attributes, "phx-window-#{phase}") != nil
  end

  defp dispatch_key(session, locator, key, phase, deadline) do
    case resolve_live_action(session, locator, deadline, &ClientDOM.target!(&1, locator)) do
      {%Session{} = session, target} ->
        state = Session.page_state(session)

        with {:ok, context} <- owning_view_context(session, target) do
          result =
            dispatch_view_event(session, fn ->
              render_view_event(state.client_dom, context, target.selector, phase, %{"key" => key})
            end)

          commit_render_result(session, state.client_dom, result, context.view)
        end

      navigation ->
        navigation
    end
  end

  @impl true
  def unwrap(%Session{} = session, fun) when is_function(fun, 1) do
    state = Session.page_state(session)
    _ignored = fun.(state.view)
    reconcile_unwrapped(session, state.client_dom)
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: {:locator, _locator}} = expectation) do
    {passed?, actual} = ClientDOM.Expectation.evaluate(client_dom(session), expectation)

    actual =
      if expectation.kind == :visible and actual == 0, do: normalize(LazyHTML.text(document(session))), else: actual

    {:ok, passed?, actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: :page, kind: :url, expected: expected}) do
    actual = Session.current_page(session).url
    {:ok, URLMatcher.matches?(expected, actual), actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{target: :page, kind: :title, expected: expected}) do
    actual =
      case session |> document() |> LazyHTML.query("title") |> Enum.at(0) do
        nil -> nil
        title -> LazyHTML.text(title)
      end

    {:ok, Expect.Internal.title_matches?(expected, actual), actual}
  end

  defp client_dom(session), do: session |> Session.page_state() |> Map.fetch!(:client_dom)
  defp document(session), do: session |> client_dom() |> Map.fetch!(:document)

  defp resolve_live_action(session, locator, deadline, action) do
    case Retry.run_current(
           session,
           deadline,
           &ActionResolver.attempt(&1, locator, action),
           &refresh/1,
           &wait_for_retry/2
         ) do
      {%Session{} = session, value} -> {session, value}
      navigation -> navigation
    end
  end

  defp eventually(session, deadline, attempt) do
    Retry.run(session, deadline, attempt, &refresh/1, &wait_for_retry/2)
  end

  defp refresh(session) do
    state = Session.page_state(session)

    try do
      case Document.render(state.document, state.view) do
        {:ok, document} ->
          Session.put_page_state(session, %{state | client_dom: ClientDOM.reconcile(state.client_dom, document)})

        {:error, redirect} ->
          follow_redirect_result(session, {:error, redirect})
      end
    catch
      :exit, reason -> follow_exit_redirect(session, reason)
    end
  end

  defp reconcile_unwrapped(session, client_dom) do
    state = Session.page_state(session)

    case left_view_event(state, 0) do
      {:redirect, redirect} ->
        follow_redirect_result(session, {:error, redirect})

      {:died, reason} ->
        raise Fluffy.LiveViewError, reason: reason

      :none ->
        try do
          state.view
          |> render()
          |> then(&commit_render_result(session, client_dom, &1))
        catch
          :exit, reason -> follow_exit_redirect(session, reason, :exit)
        end
    end
  end

  # Follows the redirect a view left when a call to it exited. An exit the
  # view left no redirect for raises a LiveViewError, or exits again when
  # `unexplained` is `:exit`.
  defp follow_exit_redirect(session, reason, unexplained \\ :raise) do
    case {exit_redirect(session), unexplained} do
      {:none, :raise} -> raise Fluffy.LiveViewError, reason: reason
      {:none, :exit} -> exit(reason)
      {redirect, _unexplained} -> follow_redirect_result(session, {:error, redirect})
    end
  end

  # A view call exits when the view went away. Return the redirect it left, or
  # `:none` when it left nothing, and raise when it died.
  defp exit_redirect(session) do
    case left_view(session) do
      {:redirect, redirect} -> redirect
      {:died, reason} -> raise Fluffy.LiveViewError, reason: reason
      :none -> :none
    end
  end

  # Reports how the view left a call that failed on it, waiting briefly for its
  # watcher.
  defp left_view(session) do
    left_view_event(Session.page_state(session), min(Session.context(session).timeout, @retry_interval))
  end

  # A redirect an event causes comes back as the event call's result, and each
  # call that sends the view an event records that it reached the view for the
  # running action. The call fails only when it finds the view already gone, so
  # the event never reached it: follow the redirect the view left instead.
  defp dispatch_view_event(session, dispatch) do
    case call_view(session, dispatch) do
      {:ok, result} -> result
      {:view_left, redirect} -> redirected(session, redirect)
    end
  end

  # render_upload can deliver a chunk and then exit on the view's redirect, so
  # once it starts, the view may have seen the action. Read the view before the
  # action first reaches it, so a view that already navigated away counts as
  # never having seen it. Later uploads follow a delivery and need no read.
  defp dispatch_view_upload(session, upload, entry_name) do
    with :ok <- read_view_before_delivery(session, upload.view) do
      ActionScope.record_delivery()
      dispatch_view_event(session, fn -> render_upload(upload, entry_name) end)
    end
  end

  defp read_view_before_delivery(session, view) do
    if ActionScope.delivered?() do
      :ok
    else
      with {:ok, _html} <- read_view(session, fn -> render(view) end), do: :ok
    end
  end

  # Reads the view without acting on it, such as its children or its upload
  # config, and reports a redirect the view left for the action to follow,
  # whether the read exits on it or its client hands it back as the value.
  defp read_view(session, read) do
    case call_view(session, read) do
      {:ok, {:error, {_kind, _options} = redirect}} -> redirected(session, redirect)
      {:ok, value} -> {:ok, value}
      {:view_left, redirect} -> redirected(session, redirect)
    end
  end

  # When the view navigated away, a call exits, or LiveViewTest hands the
  # redirect back where the caller expected a reply and the caller raises on
  # it. Either way, return the redirect the view left. Any other failure,
  # including a raise on a view that died, stands.
  defp call_view(session, call) do
    {:ok, call.()}
  rescue
    exception ->
      stacktrace = __STACKTRACE__

      with true <- redirect_reply_failure?(session, exception, stacktrace),
           {:redirect, redirect} <- left_view(session) do
        {:view_left, redirect}
      else
        _unexplained -> reraise(exception, stacktrace)
      end
  catch
    :exit, reason ->
      case exit_redirect(session) do
        :none -> raise Fluffy.LiveViewError, reason: reason
        redirect -> {:view_left, redirect}
      end
  end

  # LiveViewTest hands back a redirect in place of a reply only once the view's
  # client stopped on it, and its own code then fails on that reply. Its own
  # failures raise ArgumentError, and an error raised outside its code, such as
  # Fluffy's, is not explained by a redirect.
  defp redirect_reply_failure?(session, exception, stacktrace) do
    {_reference, _topic, proxy_pid} = Session.page_state(session).view.proxy

    not is_struct(exception, ArgumentError) and Enum.any?(stacktrace, &live_view_test_frame?/1) and
      not Process.alive?(proxy_pid)
  end

  defp live_view_test_frame?({module, _function, _arity, _location}) do
    module == Phoenix.LiveViewTest or String.starts_with?(Atom.to_string(module), "Elixir.Phoenix.LiveViewTest.")
  end

  defp live_view_test_frame?(_frame), do: false

  defp redirected(session, redirect) do
    {:navigate, session, navigation} = follow_redirect_result(session, {:error, redirect})
    {:redirected, session, navigation}
  end

  # Runs a Live action within one deadline, recording whether any of its
  # events reached the view. A navigation found before that landed before the
  # action: follow it and retry the whole action on the new page within the
  # remaining timeout, as a Playwright locator retries on the page it finds.
  # Once no budget remains, the retry is one final attempt without waiting, so
  # the action reports what it finds there, such as a missing target, and a
  # navigation that attempt finds before reaching the view fails it. Once an
  # event reached the view, the action took effect, so a navigation a later
  # step finds ends the action on the new page instead, like a browser whose
  # page navigated mid-action. A redirect the view left since Fluffy last read
  # it is followed first, so an action that never calls the view, such as a
  # plain link, acts on the new page too. A patch changes the document in
  # place, as in a browser, so the action applies the patches the view pushed
  # since and goes on in the same attempt. An action that fails before
  # following a navigation leaves its session on its page with the navigation
  # unread. `arguments` are the driver call's own, which the retry repeats.
  defp act(session, operation, arguments, action) do
    deadline = Retry.deadline(session, Keyword.validate!(List.last(arguments), [:timeout]))

    result =
      ActionScope.run(fn ->
        result =
          case unread_navigation(session) do
            %Session{} = session -> action.(session, deadline)
            redirected -> redirected
          end

        finish_action(result, ActionScope.delivered?(), operation, arguments, deadline)
      end)

    case result do
      {:retry_on_new_page, session, redirects} -> retry_on_new_page(session, redirects, operation, arguments, deadline)
      result -> result
    end
  end

  defp finish_action(result, delivered?, operation, arguments, deadline) do
    case {navigation_found(result), delivered?} do
      {{session, navigation}, true} ->
        {:navigate, session, navigation}

      {{session, navigation}, false} ->
        if Deadline.expired?(deadline) and ActionScope.final_attempt?() do
          raise Fluffy.ActionabilityError,
            action: action_label(operation, arguments),
            reason: :navigated_away,
            locator: hd(arguments)
        end

        {session, redirects} = follow_for_retry(session, navigation)
        {:retry_on_new_page, session, redirects}

      {:none, _delivered?} ->
        result
    end
  end

  # Follows a navigation an action or expectation found before reaching the
  # view, for a retry on the new page. The navigation counts toward the retry's
  # timeout, and its redirect toward the redirect limit of the retries and of
  # the redirects it leads to. Following it can fail before the session left
  # its page, such as at that limit: the session then stays there, so a failed
  # action puts back the view messages it took there. Once it left, they are moot.
  defp follow_for_retry(session, %Redirect{} = navigation) do
    state = Session.page_state(session)
    redirects = HTTP.count_redirect!(ActionScope.redirects(), URI.parse(Session.current_page(session).url))

    try do
      {Fluffy.Backend.navigate(session, %{navigation | redirects: redirects}), redirects}
    catch
      kind, reason ->
        if Session.page_state(session) != state, do: ActionScope.record_left_page()
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  # Runs outside the action's scope, as an action of its own on the page its
  # `redirects`-th redirect landed on. Expectations retry the same way.
  defp retry_on_new_page(session, redirects, operation, arguments, deadline) do
    remaining = Deadline.remaining(deadline)
    arguments = List.update_at(arguments, -1, &put_timeout(&1, remaining))
    retry = fn -> Fluffy.__dispatch_driver__(session, operation, arguments) end

    ActionScope.after_redirects(redirects, fn ->
      if remaining == 0, do: ActionScope.final_attempt(retry), else: retry.()
    end)
  end

  defp put_timeout(%Expect{} = expectation, timeout), do: Expect.Internal.merge_options(expectation, timeout: timeout)
  defp put_timeout(options, timeout), do: Keyword.put(options, :timeout, timeout)

  defp action_label(:set_checked, [_locator, desired, _options]), do: if(desired, do: :check, else: :uncheck)
  defp action_label(operation, _arguments), do: operation

  # Checks the mailbox only: a view that left or patched reports it to Fluffy
  # right away. Returns the session on the patched document, if any, or the
  # redirect the view left.
  defp unread_navigation(session) do
    case left_view_event(Session.page_state(session), 0) do
      {:redirect, redirect} -> redirected(session, redirect)
      {:died, reason} -> raise Fluffy.LiveViewError, reason: reason
      :none -> apply_unread_patches(session)
    end
  end

  # A patch also changes what the view renders, so read the view for the
  # patched document before committing the patched URL. The last patch
  # decides the URL.
  defp apply_unread_patches(session) do
    case unread_patches(Session.page_state(session).view, []) do
      [] ->
        session

      patches ->
        case refresh(session) do
          %Session{} = session -> apply_patches(session, patches)
          {:navigate, session, navigation} -> {:redirected, session, navigation}
        end
    end
  end

  defp unread_patches(view, patches) do
    case take_patch(view) do
      nil -> Enum.reverse(patches)
      patch -> unread_patches(view, [patch | patches])
    end
  end

  defp apply_patches(session, patches) do
    {_reference, {:patch, _topic, %{to: destination}}} = List.last(patches)
    session = commit_patch(session, destination)
    Enum.each(patches, &ActionScope.record_applied/1)
    session
  end

  defp commit_patch(session, destination) do
    Fluffy.Backend.navigate(session, Navigation.patch(destination, Session.page_state(session)))
  end

  # A navigation the action found before it finished, whether a view call or
  # the wait for its target saw it.
  defp navigation_found({:redirected, session, navigation}), do: {session, navigation}
  defp navigation_found({:navigate, session, navigation, {:retry, _remaining}}), do: {session, navigation}
  defp navigation_found(_result), do: :none

  # Reports how the view left: the redirect its client handed Fluffy, or what
  # its watcher saw, waiting up to `wait` for the watcher.
  defp left_view_event(state, wait) do
    case current_redirect(state.view) do
      {:error, redirect} -> {:redirect, redirect}
      nil -> live_view_event(state.watcher, wait)
    end
  end

  defp live_view_event(watcher, wait) do
    receive do
      {:fluffy_live_view, ^watcher, event} = message ->
        ActionScope.record_taken(message)
        event
    after
      wait -> :none
    end
  end

  # A patch changes the document in place, so the wait commits it and goes on
  # there, while a redirect ends the wait on the new page. A committed patch
  # stays applied even if the action fails, so the wait does not record it.
  defp wait_for_retry(session, wait) do
    state = Session.page_state(session)
    %{proxy: {reference, topic, _proxy_pid}} = state.view
    watcher = state.watcher

    receive do
      {^reference, {:patch, ^topic, %{to: destination}}} ->
        commit_patch(session, destination)

      {:fluffy_live_view, ^watcher, {:died, reason}} = message ->
        ActionScope.record_taken(message)
        raise Fluffy.LiveViewError, reason: reason

      {:fluffy_live_view, ^watcher, {:redirect, redirect}} = message ->
        ActionScope.record_taken(message)
        follow_redirect_result(session, {:error, redirect})
    after
      wait -> session
    end
  end

  defp live_click_action(target) do
    cond do
      attribute(target.attributes, "data-phx-link") != nil ->
        :render_click

      is_nil(attribute(target.attributes, "phx-click")) ->
        :none

      true ->
        phx_click_action(attribute(target.attributes, "phx-click"))
    end
  end

  defp phx_click_action("[" <> _ = encoded) do
    commands = Phoenix.json_library().decode!(encoded)

    cond do
      Enum.any?(commands, &match?([command, _] when command in ["navigate", "patch", "push"], &1)) ->
        :render_click

      Enum.any?(commands, &match?(["dispatch", %{"event" => "change"}], &1)) ->
        :dispatch_change

      true ->
        :none
    end
  end

  defp phx_click_action(_event), do: :render_click

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp commit_render_result(session, client_dom, result, event_view \\ nil)

  defp commit_render_result(session, _client_dom, {:error, {_kind, _options}} = redirect, _event_view) do
    follow_redirect_result(session, redirect)
  end

  defp commit_render_result(_session, _client_dom, {:redirected, %Session{}, _navigation} = redirected, _event_view) do
    redirected
  end

  defp commit_render_result(session, client_dom, result, _event_view) when is_binary(result) do
    state = Session.page_state(session)

    rendered =
      try do
        Document.render(state.document, state.view)
      catch
        :exit, reason -> {:exit, reason}
      end

    case rendered do
      {:ok, document} ->
        state = %{state | client_dom: ClientDOM.reconcile(client_dom, document)}
        session = session |> Session.put_page_state(state) |> prune_stale_live_uploads()

        case ClientDOM.triggered_submission(state.client_dom) do
          nil ->
            case current_patch(state.view) do
              nil -> session
              path -> {:navigate, session, Navigation.patch(path, state)}
            end

          submission ->
            {:navigate, session, Navigation.submission(submission)}
        end

      {:error, redirect} ->
        follow_redirect_result(session, {:error, redirect})

      {:exit, reason} ->
        follow_exit_redirect(session, reason)
    end
  end

  defp follow_redirect_result(session, {:error, {_kind, %{to: destination} = options}}) do
    {:navigate, session, Navigation.redirect(destination, flash: options[:flash])}
  end

  defp current_patch(view) do
    case take_patch(view) do
      {_reference, {:patch, _topic, %{to: destination}}} -> destination
      nil -> nil
    end
  end

  defp take_patch(view) do
    %{proxy: {reference, topic, _}} = view

    receive do
      {^reference, {:patch, ^topic, %{to: _destination}}} = message ->
        ActionScope.record_taken(message)
        message
    after
      0 -> nil
    end
  end

  defp current_redirect(view) do
    %{proxy: {reference, topic, _}} = view

    receive do
      {^reference, {:redirect, ^topic, %{to: _destination} = options}} = message ->
        ActionScope.record_taken(message)
        {:error, {:redirect, options}}
    after
      0 -> nil
    end
  end

  defp dispatch_live_change(session, client_dom, %Fluffy.HTML.Target{} = target) do
    with {:ok, event_context} <- owning_view_context(session, target) do
      state = Session.page_state(session)
      session = Session.put_page_state(session, %{state | client_dom: client_dom})

      case ClientDOM.change_event(client_dom, target) do
        nil ->
          session

        event ->
          payload =
            event.fields
            |> Form.to_params()
            |> Map.put("_target", event.target_name || "undefined")
            |> decode_merge_target()

          result =
            dispatch_view_event(session, fn ->
              render_view_event(client_dom, event_context, event.dispatcher_selector, :change, payload)
            end)

          commit_render_result(session, client_dom, result, event_context.view)
      end
    end
  end

  defp dispatch_live_submit(session, client_dom, submission, event_context) do
    event_view = event_context.view
    client_dom = ClientDOM.mark_form_used(client_dom, submission.form_id)

    form_selector = ClientDOM.selector_for_node_id(client_dom, submission.form_id)
    payload = Form.to_params(submission.fields)

    result =
      dispatch_view_event(session, fn ->
        render_view_event(client_dom, event_context, form_selector, :submit, payload)
      end)

    commit_render_result(session, client_dom, result, event_view)
  end

  # Resolves the view a target's bindings reach, like the LiveView client's
  # owner lookup. Teleported portal content belongs to the view that owns the
  # portal, and elements outside every LiveView fall back to the main view.
  # `root_id` is the container that LiveViewTest selectors are relative to; it
  # is nil when element/2 cannot reach the target. Finding a nested view reads
  # the view's children, so a view that navigated away reports its redirect.
  defp owning_view_context(session, target) do
    read_view(session, fn -> find_owning_view_context(Session.page_state(session).view, target) end)
  end

  defp find_owning_view_context(root_view, target) do
    result =
      Enum.reduce_while(
        target.ancestors ++ [target],
        {:ok, %{view: root_view, root_id: nil, layout?: true}},
        fn candidate, {:ok, context} ->
          case candidate_view_context(root_view, context, candidate) do
            {:ok, context} -> {:cont, {:ok, context}}
            redirect -> {:halt, redirect}
          end
        end
      )

    case result do
      {:ok, context} -> context
      redirect -> redirect
    end
  end

  defp candidate_view_context(root_view, context, candidate) do
    teleported = attribute(candidate.attributes, "data-phx-teleported")

    case {attribute(candidate.attributes, "data-phx-session"), attribute(candidate.attributes, "id")} do
      _teleported when is_binary(teleported) ->
        case find_view(root_view, teleported) do
          {:ok, nil} -> raise Fluffy.LiveViewError, reason: {:nested_live_view_not_found, teleported, root_view.id}
          {:ok, view} -> {:ok, %{view: view, root_id: nil, layout?: false}}
          redirect -> redirect
        end

      {session, id} when is_binary(session) and session != "" and id == root_view.id ->
        {:ok, %{view: root_view, root_id: candidate.id, layout?: false}}

      {session, id} when is_binary(session) and session != "" and is_binary(id) and id != "" ->
        if context.layout? do
          raise Fluffy.CapabilityError,
            capability: :root_layout_live_views,
            driver: :live,
            detail: "LiveViewTest does not connect LiveView #{inspect(id)} rendered outside the main LiveView"
        end

        with {:ok, children} <- view_children(context.view) do
          view =
            Enum.find(children, &(&1.id == id)) ||
              raise Fluffy.LiveViewError,
                reason: {:nested_live_view_not_found, id, context.view.id}

          {:ok, %{context | view: view, root_id: candidate.id}}
        end

      _not_a_live_root ->
        {:ok, context}
    end
  end

  # Returns `{:ok, view}`, or `{:ok, nil}` when no view has the id.
  defp find_view(%{id: id} = view, id), do: {:ok, view}

  defp find_view(view, id) do
    with {:ok, children} <- view_children(view) do
      Enum.reduce_while(children, {:ok, nil}, fn child, not_found ->
        case find_view(child, id) do
          {:ok, nil} -> {:cont, not_found}
          found -> {:halt, found}
        end
      end)
    end
  end

  # A view whose client stopped on a redirect hands the redirect back in place
  # of its children.
  defp view_children(view) do
    case live_children(view) do
      {:error, {_kind, _options}} = redirect -> redirect
      children -> {:ok, children}
    end
  end

  defp view_selector(_client_dom, _selector, %{root_id: nil}), do: nil
  defp view_selector(client_dom, selector, context), do: selector_for_view(client_dom, selector, context)

  defp render_view_event(client_dom, %{root_id: nil} = context, selector, kind, payload) do
    target = ClientDOM.target!(client_dom, Locator.by_css(selector))

    payload =
      if kind in [:click, :keydown, :keyup], do: Map.merge(Event.values(target.attributes), payload), else: payload

    Event.push(context.view, target, kind, payload)
  end

  defp render_view_event(client_dom, context, selector, kind, payload) do
    element = element(context.view, selector_for_view(client_dom, selector, context))

    result =
      case kind do
        :change -> render_change(element, payload)
        :submit -> render_submit(element, payload)
        :keydown -> render_keydown(element, payload)
        :keyup -> render_keyup(element, payload)
      end

    ActionScope.delivered(result)
  end

  defp selector_for_view(client_dom, selector, %{root_id: root_id}) do
    root_selector = ClientDOM.selector_for_node_id(client_dom, root_id)

    case String.replace_prefix(selector, root_selector <> " > ", "") do
      ^selector ->
        raise Fluffy.LiveViewError,
          reason: {:target_outside_nested_live_view, selector, root_selector}

      relative_selector ->
        relative_selector
    end
  end

  defp set_live_upload(session, locator, selected_files) do
    state = Session.page_state(session)

    if !ClientDOM.live_change_form?(state.client_dom, locator) do
      raise Fluffy.CapabilityError,
        capability: :file_uploads,
        driver: :live,
        detail: "LiveView-managed file uploads require a phx-change form"
    end

    target = ClientDOM.target!(state.client_dom, locator)

    with {:ok, event_context} <- owning_view_context(session, target) do
      if is_nil(event_context.root_id) do
        raise Fluffy.CapabilityError,
          capability: :file_uploads,
          driver: :live,
          detail: "LiveView-managed file uploads outside the LiveView container, such as in a portal, require Playwright"
      end

      form_id = Form.owner_id(ClientDOM.index(state.client_dom), target)

      form_selector =
        selector_for_view(state.client_dom, ClientDOM.selector_for_node_id(state.client_dom, form_id), event_context)

      upload_name = existing_upload_name!(target)
      # Validate the selection before starting an upload client it would leak.
      client_dom = ClientDOM.set_input_files(state.client_dom, locator, selected_files)

      # Starting the upload client reads the view's upload config.
      with {:ok, upload} <-
             read_view(session, fn ->
               file_input!(session, event_context.view, form_selector, upload_name, selected_files)
             end) do
        start_live_upload(session, client_dom, selected_files, target, event_context, form_id, form_selector, upload)
      end
    end
  end

  defp file_input!(session, view, form_selector, upload_name, selected_files) do
    entries =
      Enum.map(selected_files, fn selected_file ->
        %{
          content: selected_file.bytes,
          last_modified: nil,
          name: selected_file.name,
          size: selected_file.size,
          type: selected_file.content_type
        }
      end)

    UploadCompat.file_input!(view, form_selector, upload_name, entries, Session.context(session).http.endpoint)
  end

  defp start_live_upload(session, client_dom, selected_files, target, event_context, form_id, form_selector, upload) do
    auto_upload? = live_auto_upload?(target)
    append? = live_multiple_file_input?(target) and live_upload_present?(session, form_id)
    session = if append?, do: session, else: release_live_upload_for_form(session, form_id)

    :ok =
      Fluffy.Backend.Phoenix.register_process(
        session.runtime,
        :upload_client,
        upload.pid,
        Session.context(session).timeout
      )

    # The selection-triggered `phx-change` may replace or remove this input.
    # Register its client state before reconciling that render, so stale-input
    # cleanup can release the upload rather than leaving an unreachable ref.
    session =
      put_live_upload(
        session,
        client_dom,
        form_id,
        target,
        upload,
        selected_files,
        false,
        append?
      )

    result =
      dispatch_view_event(session, fn ->
        event_context.view
        |> element(form_selector)
        |> render_change(upload)
        |> ActionScope.delivered()
      end)

    case commit_render_result(session, client_dom, result, event_context.view) do
      %Session{} = session when auto_upload? ->
        if live_upload_present?(session, form_id) do
          case dispatch_live_upload(
                 session,
                 upload,
                 upload_entry_names(upload),
                 event_context
               ) do
            {:ok, session} -> mark_live_upload_uploaded(session, form_id, upload.pid)
            {:entry_error, session} -> session
            {:navigation, navigation} -> navigation
          end
        else
          session
        end

      %Session{} = session ->
        session

      navigation ->
        navigation
    end
  end

  defp put_live_upload(session, client_dom, form_id, target, upload, selected_files, uploaded?, append?) do
    state = Session.page_state(session)

    live_uploads =
      UploadState.put(
        state.live_uploads,
        form_id,
        ClientDOM.target_identity(target),
        target.selector,
        upload,
        selected_files,
        uploaded: uploaded?,
        append: append?
      )

    state
    |> Map.put(:client_dom, client_dom)
    |> Map.put(:live_uploads, live_uploads)
    |> then(&Session.put_page_state(session, &1))
  end

  defp live_upload_present?(session, form_id) do
    session |> Session.page_state() |> Map.fetch!(:live_uploads) |> UploadState.present?(form_id)
  end

  defp mark_live_upload_uploaded(session, form_id, upload_pid) do
    state = Session.page_state(session)

    state = %{
      state
      | live_uploads: UploadState.mark_uploaded(state.live_uploads, form_id, upload_pid)
    }

    Session.put_page_state(session, state)
  end

  defp live_auto_upload?(target) do
    attribute(target.attributes, "data-phx-auto-upload") not in [nil, false, "false"]
  end

  defp live_multiple_file_input?(target) do
    attribute(target.attributes, "multiple") not in [nil, false, "false"]
  end

  defp existing_upload_name!(target) do
    case attribute(target.attributes, "name") do
      name when is_binary(name) and name != "" ->
        case existing_atom(name) do
          {:ok, atom} ->
            atom

          :error ->
            raise Fluffy.CapabilityError,
              capability: :file_uploads,
              driver: :live,
              detail: "LiveView-managed file uploads require the input name to be an existing upload atom"
        end

      _missing_name ->
        raise Fluffy.CapabilityError,
          capability: :file_uploads,
          driver: :live,
          detail: "LiveView-managed file uploads require a named file input"
    end
  end

  defp existing_atom(name) do
    {:ok, String.to_existing_atom(name)}
  rescue
    ArgumentError -> :error
  end

  defp live_upload_for_submit(session, target) do
    state = Session.page_state(session)

    case Form.owner_id(ClientDOM.index(state.client_dom), target) do
      nil ->
        :none

      form_id ->
        case UploadState.get(state.live_uploads, form_id) do
          nil -> :none
          upload_state -> {:ok, form_id, upload_state}
        end
    end
  end

  defp release_live_upload_for_form(session, form_id) do
    state = Session.page_state(session)

    case UploadState.fetch(state.live_uploads, form_id) do
      {:ok, upload_state} ->
        release_live_upload_clients(session, upload_state)
        {_form, live_uploads} = UploadState.delete_form(state.live_uploads, form_id)
        Session.put_page_state(session, %{state | live_uploads: live_uploads})

      :error ->
        session
    end
  end

  # A LiveView cancel control carries the selected entry's `phx-value-ref`.
  # Once its event removes that entry from the rendered page, the test upload
  # client is unreachable and must be released before a later submit can try
  # to transfer the cancelled bytes.
  defp release_cancelled_live_upload(session, target) do
    entry_ref = attribute(target.attributes, "phx-value-ref")
    state = Session.page_state(session)

    case find_live_upload_entry(state, entry_ref) do
      {form_id, upload_state, entry_upload} when is_binary(entry_ref) ->
        release_missing_live_upload_entry(
          session,
          state.client_dom,
          form_id,
          upload_state,
          entry_upload,
          entry_ref
        )

      _no_matching_entry ->
        session
    end
  end

  defp release_missing_live_upload_entry(session, client_dom, form_id, upload_state, entry_upload, entry_ref) do
    if live_upload_entry_rendered?(client_dom, entry_ref) do
      session
    else
      remaining_entries = Enum.reject(entry_upload.entries, &(&1.ref == entry_ref))
      sync_cancelled_live_upload(session, form_id, upload_state, entry_upload, remaining_entries)
    end
  end

  defp sync_cancelled_live_upload(session, form_id, upload_state, entry_upload, []) do
    session = release_live_upload_client(session, entry_upload.upload)
    session = remove_live_upload(session, form_id, entry_upload.upload.pid)

    selected_files =
      case UploadState.get(Session.page_state(session).live_uploads, form_id) do
        nil -> []
        form -> UploadState.selected_files(form.batches)
      end

    put_live_upload_files(session, upload_state, selected_files)
  end

  defp sync_cancelled_live_upload(session, form_id, upload_state, entry_upload, remaining_entries) do
    session
    |> put_live_upload_files(upload_state, Enum.map(remaining_entries, & &1.selected_file))
    |> put_live_upload_entries(form_id, entry_upload.upload.pid, remaining_entries)
  end

  defp live_upload_entry_rendered?(client_dom, entry_ref) do
    selector = ~s([phx-value-ref="#{entry_ref}"])
    ClientDOM.resolve(client_dom, Locator.by_css(selector)) != []
  end

  defp put_live_upload_files(session, %{input_selector: selector}, selected_files) do
    state = Session.page_state(session)
    locator = Locator.by_css(selector)
    client_dom = ClientDOM.set_input_files(state.client_dom, locator, selected_files)
    Session.put_page_state(session, %{state | client_dom: client_dom})
  end

  defp put_live_upload_entries(session, form_id, upload_pid, entries) do
    state = Session.page_state(session)
    live_uploads = UploadState.put_entries(state.live_uploads, form_id, upload_pid, entries)
    Session.put_page_state(session, %{state | live_uploads: live_uploads})
  end

  defp dispatch_live_upload_submit(session, _client_dom, form_id, upload_state, submission, event_context) do
    # LiveView marks the form before any upload runs, so the marks survive a
    # submit that an upload entry error blocks.
    state = Session.page_state(session)
    session = Session.put_page_state(session, %{state | client_dom: ClientDOM.mark_form_used(state.client_dom, form_id)})

    upload_result =
      Enum.reduce_while(upload_state.batches, {:ok, session}, fn entry_upload, {:ok, session} ->
        case entry_upload do
          %{uploaded?: true} ->
            {:cont, {:ok, session}}

          %{entries: entries, upload: upload} ->
            case dispatch_live_upload(session, upload, entry_names(entries), event_context) do
              {:ok, session} -> {:cont, {:ok, session}}
              {:entry_error, session} -> {:halt, {:entry_error, session}}
              {:navigation, navigation} -> {:halt, {:navigation, navigation}}
            end
        end
      end)

    case upload_result do
      {:ok, session} ->
        dispatch_live_upload_submit_event(session, form_id, submission, event_context)

      {:entry_error, session} ->
        session

      {:navigation, navigation} ->
        navigation
    end
  end

  defp dispatch_live_upload_submit_event(session, form_id, submission, event_context) do
    state = Session.page_state(session)

    form_selector = ClientDOM.selector_for_node_id(state.client_dom, form_id)
    payload = Form.to_params(submission.fields)

    submit_result =
      dispatch_view_event(session, fn ->
        render_view_event(state.client_dom, event_context, form_selector, :submit, payload)
      end)

    case commit_render_result(session, state.client_dom, submit_result, event_context.view) do
      %Session{} = session ->
        release_live_upload_for_form(session, form_id)

      {kind, %Session{} = session, navigation} when kind in [:navigate, :redirected] ->
        {kind, release_live_upload_for_form(session, form_id), navigation}
    end
  end

  defp find_live_upload_entry(state, entry_ref) when is_binary(entry_ref) do
    UploadState.find_entry(state.live_uploads, entry_ref)
  end

  defp find_live_upload_entry(_state, _entry_ref), do: nil

  defp remove_live_upload(session, form_id, upload_pid) do
    state = Session.page_state(session)
    live_uploads = UploadState.remove_batch(state.live_uploads, form_id, upload_pid)
    Session.put_page_state(session, %{state | live_uploads: live_uploads})
  end

  defp release_live_upload_clients(session, %{batches: batches}) do
    Enum.each(batches, &release_live_upload_client(session, &1.upload))
  end

  defp release_live_upload_client(session, upload) do
    release_upload_client(session, upload)
    session
  end

  defp dispatch_live_upload(session, upload, entry_names, event_context) do
    Enum.reduce_while(entry_names, {:ok, session}, fn entry_name, {:ok, session} ->
      upload_result = dispatch_view_upload(session, upload, entry_name)

      case upload_result do
        # A progress callback that navigates returns its redirect, which
        # commits like any other render result.
        {:error, entry_errors} when not is_tuple(entry_errors) ->
          {:halt, {:entry_error, session}}

        _result ->
          state = Session.page_state(session)

          case commit_render_result(session, state.client_dom, upload_result, event_context.view) do
            %Session{} = session -> {:cont, {:ok, session}}
            navigation -> {:halt, {:navigation, navigation}}
          end
      end
    end)
  end

  defp upload_entry_names(upload), do: Enum.map(upload.entries, &Map.fetch!(&1, "name"))
  defp entry_names(entries), do: Enum.map(entries, & &1.name)

  defp prune_stale_live_uploads(%Session{} = session) do
    state = Session.page_state(session)

    {live_uploads, stale_uploads} =
      UploadState.prune(state.live_uploads, fn upload_state ->
        ClientDOM.target_identity_present?(state.client_dom, upload_state.input_identity)
      end)

    Enum.each(stale_uploads, &release_live_upload_clients(session, &1))

    Session.put_page_state(session, %{state | live_uploads: live_uploads})
  end

  defp release_upload_client(session, upload) do
    Fluffy.SessionRuntime.release(session.runtime, {:upload_client, upload.pid})

    UploadCompat.stop(upload)
  end

  # Keep this in step with Phoenix.LiveView.Channel's `_target` decoding. The
  # browser sends the input name as a string; the channel query-decodes that
  # name and walks the resulting single keyspace to produce the target path.
  defp decode_merge_target(%{"_target" => target} = params) when is_list(target), do: params

  defp decode_merge_target(%{"_target" => target} = params) when is_binary(target) do
    keyspace = target |> Plug.Conn.Query.decode() |> gather_keys([])
    Map.put(params, "_target", Enum.reverse(keyspace))
  end

  defp decode_merge_target(%{} = params), do: params

  defp gather_keys(%{} = map, acc) do
    case :maps.next(:maps.iterator(map)) do
      {key, value, _iterator} -> gather_keys(value, [key | acc])
      :none -> acc
    end
  end

  defp gather_keys([], acc), do: acc
  defp gather_keys([%{} = map], acc), do: gather_keys(map, acc)
  defp gather_keys(_value, acc), do: acc

  defp normalize(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
