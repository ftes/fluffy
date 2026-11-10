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
  alias Fluffy.HTML.Semantics
  alias Fluffy.HTML.Target
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
      {:redirected, session, navigation} ->
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
        {%Session{} = session, {client_dom, target}} -> commit_user_click(session, client_dom, target)
        navigation -> navigation
      end
    end)
  end

  # A browser click that toggles a checkbox or selects a radio fires input and
  # change after the click event, so it sends phx-click and then phx-change,
  # like check/2.
  defp commit_user_click(session, client_dom, target) do
    if Semantics.input_type(target) in ["checkbox", "radio"] and client_dom != Session.page_state(session).client_dom do
      commit_checked(session, client_dom, target)
    else
      commit_click(session, client_dom, target)
    end
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
    case click_binding(client_dom, target) do
      nil ->
        commit_default_click(session, client_dom, target, event_context)

      binding ->
        case live_click_action(binding) do
          :none ->
            commit_default_click(session, client_dom, target, event_context)

          action when binding.id == target.id ->
            commit_click_binding(session, client_dom, binding, event_context, action)

          action ->
            commit_ancestor_click(session, client_dom, binding, target, event_context, action)
        end
    end
  end

  # The click event reaches the ancestor's binding before the target's own
  # default action, such as submitting its form, takes place.
  defp commit_ancestor_click(session, client_dom, binding, target, event_context, action) do
    identity = node_identity(client_dom, target)

    with %Session{} = session <- commit_click_binding(session, client_dom, binding, event_context, action) do
      client_dom = Session.page_state(session).client_dom

      with %Target{} = target <- find_by_identity(client_dom, identity),
           {:ok, event_context} <- owning_view_context(session, target) do
        commit_default_click(session, client_dom, target, event_context)
      else
        nil -> session
        redirected -> redirected
      end
    end
  end

  # Like the LiveView client's closestPhxBinding, a click goes to the closest
  # element with phx-click that is not disabled, up to its LiveView's container.
  # A LiveView link handles its own click.
  defp click_binding(client_dom, target) do
    if attribute(target.attributes, "data-phx-link") || attribute(target.attributes, "phx-click") do
      target
    else
      target.ancestors
      |> Enum.reverse()
      |> Enum.reduce_while(nil, fn ancestor, nil ->
        cond do
          attribute(ancestor.attributes, "data-phx-session") -> {:halt, nil}
          attribute(ancestor.attributes, "phx-click") && not disabled_control?(ancestor) -> {:halt, ancestor}
          true -> {:cont, nil}
        end
      end)
      |> case do
        nil -> nil
        ancestor -> DocumentIndex.target_by_id(ClientDOM.index(client_dom), ancestor.id)
      end
    end
  end

  defp disabled_control?(element) do
    element.tag in ~w(button fieldset input optgroup option select textarea) and
      List.keymember?(element.attributes, "disabled", 0)
  end

  defp commit_click_binding(session, client_dom, binding, event_context, :dispatch_change),
    do: dispatch_live_click_change(session, client_dom, binding, event_context)

  defp commit_click_binding(session, client_dom, binding, event_context, :render_click) do
    result =
      dispatch_view_event(session, fn ->
        Click.render(event_context.view, client_dom, binding, view_selector(client_dom, binding.selector, event_context))
      end)

    case commit_render_result(session, client_dom, result) do
      %Session{} = session -> release_cancelled_live_upload(session, binding)
      navigation -> navigation
    end
  end

  defp commit_default_click(session, client_dom, target, event_context) do
    state = Session.page_state(session)
    session = Session.put_page_state(session, %{state | client_dom: client_dom})

    case ClientDOM.form_submission(client_dom, target, :live) do
      %{phx_submit?: true} = submission ->
        case live_upload_for_submit(session, target) do
          {:ok, form_id, upload} ->
            dispatch_live_upload_submit(session, form_id, upload, submission)

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

  defp dispatch_live_click_change(session, client_dom, target, event_context) do
    state = Session.page_state(session)
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

        commit_render_result(session, client_dom, result)
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
    fill_value(session, :fill, [locator, value, options], locator, value)
  end

  @impl true
  def clear(%Session{} = session, %Locator{} = locator, options \\ []) do
    fill_value(session, :clear, [locator, options], locator, "")
  end

  defp fill_value(session, operation, arguments, locator, value) do
    act(session, operation, arguments, fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &ClientDOM.fill(&1, locator, value, :live, operation)) do
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
    identity = node_identity(client_dom, target)

    case commit_click(session, client_dom, target) do
      %Session{} = session ->
        client_dom = Session.page_state(session).client_dom

        # A selector such as :checked stops matching after uncheck. Follow the
        # original control across any click patch instead of resolving it again,
        # and find the view that owns it there, since the click may have moved it.
        case find_by_identity(client_dom, identity) do
          nil -> session
          target -> dispatch_live_change(session, client_dom, target)
        end

      navigation ->
        navigation
    end
  end

  defp node_identity(client_dom, target), do: Map.fetch!(ClientDOM.index(client_dom).nodes_by_id, target.id).identity

  # A patch keeps a node's identity but can move or remove the node, so a step
  # that follows it goes on only if this finds the node.
  defp find_by_identity(client_dom, identity) do
    index = ClientDOM.index(client_dom)

    case Enum.find(index.entries, &(&1.identity == identity)) do
      nil -> nil
      entry -> DocumentIndex.target_by_id(index, entry.id)
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
        {%Session{} = session, target} -> dispatch_keys(session, target, key)
        navigation -> navigation
      end
    end)
  end

  # A browser sends keyup right after keydown, before the keydown's patch comes
  # back, so a keyup after a keydown uses the binding its element had when the
  # press started, whatever the patch then removes, moves, or rebinds. Only the
  # first phase meets the document the target was found in.
  defp dispatch_keys(session, target, key) do
    phases = Enum.filter([:keydown, :keyup], &key_binding?(target, &1))
    [first | rest] = if phases == [], do: [:keydown], else: phases

    with {:ok, context} <- owning_view_context(session, target),
         %Session{} = session <- dispatch_key(session, context, target, key, first) do
      if rest == [], do: session, else: dispatch_bound_keyup(session, context, target, key)
    end
  end

  defp key_binding?(target, phase) do
    attribute(target.attributes, "phx-#{phase}") != nil or
      attribute(target.attributes, "phx-window-#{phase}") != nil
  end

  defp dispatch_key(session, context, target, key, phase) do
    state = Session.page_state(session)

    result =
      dispatch_view_event(session, fn ->
        render_view_event(state.client_dom, context, target.selector, phase, %{"key" => key})
      end)

    commit_render_result(session, state.client_dom, result)
  end

  defp dispatch_bound_keyup(session, context, target, key) do
    state = Session.page_state(session)

    case read_view(session, fn -> with {:ok, view} <- find_view(state.view, context.view.id), do: view end) do
      # The keydown removed the nested view that owns the target.
      {:ok, nil} ->
        session

      {:ok, view} ->
        payload = Map.put(Event.key_values(target.attributes), "key", key)
        result = dispatch_view_event(session, fn -> Event.push(view, target, :keyup, payload) end)
        commit_render_result(session, state.client_dom, result)

      redirected ->
        redirected
    end
  end

  @impl true
  def unwrap(%Session{} = session, fun) when is_function(fun, 1) do
    {:return, _ignored, outcome} = unwrap_and_return(session, fun)
    outcome
  end

  @impl true
  def unwrap_and_return(%Session{} = session, fun) when is_function(fun, 1) do
    state = Session.page_state(session)
    result = fun.(state.view)
    {:return, result, reconcile_unwrapped(session, state.client_dom)}
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
        # The render syncs with the view, so a patch the callback set off without
        # waiting has arrived when the result commits it.
        try do
          state.view |> render() |> then(&commit_render_result(session, client_dom, &1))
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
      redirected -> redirected
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
      result -> result
    end
  end

  # When the view navigated away, a call exits, or LiveViewTest hands the
  # redirect back where the caller expected a reply and the caller raises on
  # it. Either way, follow the redirect the view left. Any other failure,
  # including a raise on a view that died, stands.
  defp call_view(session, call) do
    {:ok, call.()}
  rescue
    exception ->
      stacktrace = __STACKTRACE__

      with true <- redirect_reply_failure?(session, exception),
           {:redirect, redirect} <- left_view(session) do
        redirected(session, redirect)
      else
        _unexplained -> reraise(exception, stacktrace)
      end
  catch
    :exit, reason ->
      {:navigate, session, navigation} = follow_exit_redirect(session, reason)
      {:redirected, session, navigation}
  end

  # LiveViewTest hands back a redirect in place of a reply only once the view's
  # client stopped on it, and its own code then fails on that reply. Usage
  # errors raise ArgumentError, and those stand.
  defp redirect_reply_failure?(session, exception) do
    {_reference, _topic, proxy_pid} = Session.page_state(session).view.proxy
    not is_struct(exception, ArgumentError) and not Process.alive?(proxy_pid)
  end

  defp redirected(session, redirect) do
    {:navigate, session, navigation} = follow_redirect_result(session, {:error, redirect})
    {:redirected, session, navigation}
  end

  # Runs a Live action within one deadline, recording whether any of its
  # events reached the view. A navigation found before that landed before the
  # action: follow it and retry the whole action on the new page within the
  # remaining timeout, as a Playwright locator retries on the page it finds.
  # A navigation found once no budget remains fails the action instead, as
  # Playwright never acts past its deadline, and leaves the navigation unread
  # for the session's next call. One whose following used up the budget fails
  # it too, on the new page. Once an event reached the view, the action took
  # effect, so a navigation a later step finds ends the action on the new page
  # instead, like a browser whose page navigated mid-action. A redirect the view left since Fluffy last read
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
      {:retry_on_new_page, session, redirects} ->
        if Deadline.expired?(deadline), do: raise_navigated_away(operation, arguments)
        retry_on_new_page(session, redirects, operation, arguments, deadline)

      result ->
        result
    end
  end

  defp finish_action(result, delivered?, operation, arguments, deadline) do
    case {navigation_found(result), delivered?} do
      {{session, navigation}, true} ->
        {:navigate, session, navigation}

      {{session, navigation}, false} ->
        if Deadline.expired?(deadline), do: raise_navigated_away(operation, arguments)

        {session, redirects} = follow_for_retry(session, navigation)
        {:retry_on_new_page, session, redirects}

      {:none, _delivered?} ->
        result
    end
  end

  # Follows a navigation an action or expectation found before reaching the
  # view, for a retry on the new page. The navigation counts toward the retry's
  # timeout, and its redirect toward the redirect limit of the retries and of
  # the redirects it leads to.
  defp follow_for_retry(session, %Redirect{} = navigation) do
    redirects = HTTP.count_redirect!(ActionScope.redirects(), URI.parse(Session.current_page(session).url))
    {Fluffy.Backend.navigate(session, %{navigation | redirects: redirects}), redirects}
  end

  # Runs outside the action's scope, as an action of its own on the page its
  # `redirects`-th redirect landed on. Expectations retry the same way.
  defp retry_on_new_page(session, redirects, operation, arguments, deadline) do
    remaining = Deadline.remaining(deadline)
    arguments = List.update_at(arguments, -1, &put_timeout(&1, remaining))
    ActionScope.after_redirects(redirects, fn -> Fluffy.__dispatch_driver__(session, operation, arguments) end)
  end

  defp put_timeout(%Expect{} = expectation, timeout), do: Expect.Internal.merge_options(expectation, timeout: timeout)
  defp put_timeout(options, timeout), do: Keyword.put(options, :timeout, timeout)

  defp raise_navigated_away(operation, arguments) do
    raise Fluffy.ActionabilityError,
      action: action_label(operation, arguments),
      reason: :navigated_away,
      locator: hd(arguments)
  end

  defp action_label(:set_checked, [_locator, desired, _options]), do: if(desired, do: :check, else: :uncheck)
  defp action_label(operation, _arguments), do: operation

  # Checks the mailbox only: a view that left or patched reports it to Fluffy
  # right away. Returns the session on the patched document, if any, or the
  # redirect the view left.
  defp unread_navigation(session) do
    case left_view_event(Session.page_state(session), 0) do
      {:redirect, redirect} -> redirected(session, redirect)
      :none -> apply_unread_patches(session)
      {:died, reason} -> raise_after_patches(session, reason)
    end
  end

  # A patch is committed as it is taken, and the last one decides the URL. It
  # also changes what the view renders, so the action reads the view for the
  # patched document before it goes on.
  defp apply_unread_patches(session) do
    case last_patch(Session.page_state(session).view) do
      nil ->
        session

      destination ->
        case session |> commit_patch(destination) |> refresh() do
          %Session{} = session -> session
          {:navigate, session, navigation} -> {:redirected, session, navigation}
        end
    end
  end

  # An action keeps a patch the view pushed before it died, however soon the
  # watcher reported the death.
  defp raise_after_patches(session, reason) do
    apply_last_patch(session)
    raise Fluffy.LiveViewError, reason: reason
  end

  defp apply_last_patch(session) do
    case last_patch(Session.page_state(session).view) do
      nil -> session
      destination -> commit_patch(session, destination)
    end
  end

  defp last_patch(%{proxy: {reference, topic, _proxy_pid}} = view, last \\ nil) do
    receive do
      {^reference, {:patch, ^topic, %{to: destination}}} -> last_patch(view, destination)
    after
      0 -> last
    end
  end

  defp commit_patch(session, destination) do
    Fluffy.Backend.navigate(session, Navigation.patch(destination, Session.page_state(session)))
  end

  # A navigation the action found before it finished, whether a view call or
  # the wait for its target saw it.
  defp navigation_found({:redirected, session, navigation}), do: {session, navigation}
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
        leave_unread(message)
        event
    after
      wait -> :none
    end
  end

  # A view leaves once, and that stays true until the session leaves its page,
  # so reading how it left leaves the message for the session's next call. A
  # call that fails before following it then needs no undo.
  defp leave_unread(message), do: send(self(), message)

  # A patch changes the document in place, so the wait commits it and goes on
  # there, while a redirect ends the wait on the new page. A committed patch
  # stays applied even if the action fails.
  defp wait_for_retry(session, wait) do
    state = Session.page_state(session)
    %{proxy: {reference, topic, _proxy_pid}} = state.view
    watcher = state.watcher

    receive do
      {^reference, {:patch, ^topic, %{to: destination}}} ->
        commit_patch(session, destination)

      {:fluffy_live_view, ^watcher, {:died, reason}} = message ->
        leave_unread(message)
        raise Fluffy.LiveViewError, reason: reason

      {:fluffy_live_view, ^watcher, {:redirect, redirect}} = message ->
        leave_unread(message)
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

  defp commit_render_result(session, client_dom, result, after_render \\ &prune_stale_live_uploads/1)

  defp commit_render_result(session, _client_dom, {:error, {_kind, _options}} = redirect, _after_render) do
    follow_redirect_result(session, redirect)
  end

  defp commit_render_result(_session, _client_dom, {:redirected, %Session{}, _nav} = redirected, _after_render) do
    redirected
  end

  # Patches are committed before the render, so it shows the last of them.
  # LiveViewTest answers nil when the event's nested view was removed before its
  # reply; the page is still whatever the root view renders now.
  defp commit_render_result(session, client_dom, result, after_render) when is_binary(result) or is_nil(result) do
    session = apply_last_patch(session)
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
        session = session |> Session.put_page_state(state) |> after_render.()

        case ClientDOM.triggered_submission(state.client_dom) do
          nil ->
            session

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

  defp current_redirect(view) do
    %{proxy: {reference, topic, _}} = view

    receive do
      {^reference, {:redirect, ^topic, %{to: _destination} = options}} = message ->
        leave_unread(message)
        {:error, {:redirect, options}}
    after
      0 -> nil
    end
  end

  defp dispatch_live_change(session, client_dom, %Target{} = target) do
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

          commit_render_result(session, client_dom, result)
      end
    end
  end

  defp dispatch_live_submit(session, client_dom, submission, event_context) do
    client_dom = ClientDOM.mark_form_used(client_dom, submission.form_id)

    form_selector = ClientDOM.selector_for_node_id(client_dom, submission.form_id)
    payload = Form.to_params(submission.fields)

    result =
      dispatch_view_event(session, fn ->
        render_view_event(client_dom, event_context, form_selector, :submit, payload)
      end)

    commit_render_result(session, client_dom, result)
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

  # LiveViewTest's element form events fill in the form as the server rendered
  # it, which brings back a checkbox the user unchecked or an option they
  # deselected. Push the browser's serialization instead, with the form's
  # phx-value-* attributes winning over fields, as the LiveView client does.
  defp render_view_event(client_dom, context, selector, kind, payload) when kind in [:change, :submit] do
    target = ClientDOM.target!(client_dom, Locator.by_css(selector))
    form = if target.tag == "form", do: target, else: DocumentIndex.form_owner(ClientDOM.index(client_dom), target)
    form_values = if form, do: Event.values(form.attributes), else: %{}

    Event.push(context.view, target, kind, Map.merge(payload, form_values))
  end

  defp render_view_event(client_dom, %{root_id: nil} = context, selector, kind, payload) do
    target = ClientDOM.target!(client_dom, Locator.by_css(selector))

    payload =
      case kind do
        :click -> Map.merge(Event.values(target.attributes), payload)
        kind when kind in [:keydown, :keyup] -> Map.merge(Event.key_values(target.attributes), payload)
      end

    Event.push(context.view, target, kind, payload)
  end

  defp render_view_event(client_dom, context, selector, kind, payload) do
    element = element(context.view, selector_for_view(client_dom, selector, context))

    result =
      case kind do
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

      index = ClientDOM.index(state.client_dom)
      form_id = Form.owner_id(index, target)
      ensure_upload_form_id!(DocumentIndex.target_by_id(index, form_id))

      form_selector =
        selector_for_view(state.client_dom, ClientDOM.selector_for_node_id(state.client_dom, form_id), event_context)

      input_selector = selector_for_view(state.client_dom, target.selector, event_context)
      upload_name = existing_upload_name!(target)
      # Validate the selection before starting an upload client it would leak.
      client_dom = ClientDOM.set_input_files(state.client_dom, locator, selected_files)

      # Starting the upload client reads the view's upload config.
      with {:ok, upload} <-
             read_view(session, fn ->
               file_input!(session, event_context.view, form_selector, upload_name, selected_files)
             end) do
        upload = UploadCompat.at_input(upload, input_selector)
        form_key = node_identity(state.client_dom, %{id: form_id})
        start_live_upload(session, client_dom, selected_files, target, event_context, form_key, form_selector, upload)
      end
    end
  end

  # A form without an id has only a position, which a patch can shift or hand
  # to another form. LiveView's own form recovery needs an id too.
  defp ensure_upload_form_id!(form) do
    if is_nil(attribute(form.attributes, "id")) do
      raise ArgumentError,
            "set_input_files/3 on a LiveView upload requires its form to have an id; give the form an id"
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

  defp start_live_upload(session, client_dom, selected_files, target, event_context, form_key, form_selector, upload) do
    auto_upload? = live_auto_upload?(target)
    append? = live_multiple_file_input?(target) and live_upload_present?(session, form_key)
    session = if append?, do: session, else: release_live_upload_for_form(session, form_key)

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
        form_key,
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

    case commit_render_result(session, client_dom, result) do
      %Session{} = session when auto_upload? ->
        if live_upload_present?(session, form_key) do
          case dispatch_live_upload(session, form_key, upload, upload_entry_names(upload)) do
            {:ok, session} -> session |> mark_live_upload_uploaded(form_key, upload.pid) |> prune_stale_live_uploads()
            {reason, session} when reason in [:entry_error, :input_gone] -> prune_stale_live_uploads(session)
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
        node_identity(client_dom, target),
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
        form_key = node_identity(state.client_dom, %{id: form_id})

        case UploadState.get(state.live_uploads, form_key) do
          nil -> :none
          upload_state -> {:ok, form_key, upload_state}
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

  defp put_live_upload_files(session, %{input_identity: identity}, selected_files) do
    state = Session.page_state(session)

    # A finished upload outlives its input, so the input may be gone.
    case find_by_identity(state.client_dom, identity) do
      nil ->
        session

      input ->
        client_dom = ClientDOM.set_input_files(state.client_dom, Locator.by_css(input.selector), selected_files)
        Session.put_page_state(session, %{state | client_dom: client_dom})
    end
  end

  defp put_live_upload_entries(session, form_id, upload_pid, entries) do
    state = Session.page_state(session)
    live_uploads = UploadState.put_entries(state.live_uploads, form_id, upload_pid, entries)
    Session.put_page_state(session, %{state | live_uploads: live_uploads})
  end

  defp dispatch_live_upload_submit(session, form_key, upload_state, submission) do
    # LiveView marks the form before any upload runs, so the marks survive a
    # submit that an upload entry error blocks.
    state = Session.page_state(session)
    form = find_by_identity(state.client_dom, form_key)
    session = Session.put_page_state(session, %{state | client_dom: ClientDOM.mark_form_used(state.client_dom, form.id)})

    upload_result =
      Enum.reduce_while(upload_state.batches, {:ok, session}, fn entry_upload, {:ok, session} ->
        case entry_upload do
          %{uploaded?: true} ->
            {:cont, {:ok, session}}

          %{entries: entries, upload: upload} ->
            case dispatch_live_upload(session, form_key, upload, entry_names(entries)) do
              {:ok, session} -> {:cont, {:ok, session}}
              {:input_gone, session} -> {:halt, {:input_gone, session}}
              {:entry_error, session} -> {:halt, {:entry_error, session}}
              {:navigation, navigation} -> {:halt, {:navigation, navigation}}
            end
        end
      end)

    case upload_result do
      {:ok, session} ->
        submit_after_uploads(session, form_key, submission)

      {reason, session} when reason in [:entry_error, :input_gone] ->
        prune_stale_live_uploads(session)

      {:navigation, navigation} ->
        navigation
    end
  end

  # A patch during the uploads can move or remove the form.
  defp submit_after_uploads(session, form_key, submission) do
    case current_upload_form(session, form_key) do
      nil ->
        session

      form ->
        with {:ok, event_context} <- owning_view_context(session, form) do
          dispatch_live_upload_submit_event(session, form_key, form, submission, event_context)
        end
    end
  end

  # A file input always has an id, so its form is the one to trust. Only when
  # the input is gone or left its form does the form's own identity decide.
  defp current_upload_form(session, form_key) do
    state = Session.page_state(session)
    form_of_upload_input(state, form_key) || find_by_identity(state.client_dom, form_key)
  end

  defp form_of_upload_input(state, form_key) do
    with %{} = input <- live_upload_input(state, form_key) do
      index = ClientDOM.index(state.client_dom)
      DocumentIndex.target_by_id(index, Form.owner_id(index, input))
    end
  end

  defp live_upload_input(state, form_key) do
    with %{input_identity: identity} <- UploadState.get(state.live_uploads, form_key) do
      find_by_identity(state.client_dom, identity)
    end
  end

  defp dispatch_live_upload_submit_event(session, form_key, form, submission, event_context) do
    state = Session.page_state(session)

    payload = Form.to_params(submission.fields)

    submit_result =
      dispatch_view_event(session, fn ->
        render_view_event(state.client_dom, event_context, form.selector, :submit, payload)
      end)

    case commit_render_result(session, state.client_dom, submit_result) do
      %Session{} = session ->
        release_live_upload_for_form(session, form_key)

      {kind, %Session{} = session, navigation} when kind in [:navigate, :redirected] ->
        {kind, release_live_upload_for_form(session, form_key), navigation}
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

  defp dispatch_live_upload(session, form_key, upload, entry_names) do
    Enum.reduce_while(entry_names, {:ok, session}, fn entry_name, {:ok, session} ->
      # A patch during the uploads can remove the input, releasing its client,
      # or move it away from its client's selector.
      with %{} = input <- live_upload_input(Session.page_state(session), form_key),
           {:ok, upload} <- upload_at_current_input(session, input, upload) do
        dispatch_live_upload_entry(session, upload, entry_name)
      else
        nil -> {:halt, {:input_gone, session}}
        navigation -> {:halt, {:navigation, navigation}}
      end
    end)
  end

  defp upload_at_current_input(session, input, upload) do
    client_dom = Session.page_state(session).client_dom

    with {:ok, context} <- owning_view_context(session, input) do
      {:ok, UploadCompat.at_input(upload, selector_for_view(client_dom, input.selector, context))}
    end
  end

  defp dispatch_live_upload_entry(session, upload, entry_name) do
    upload_result = dispatch_view_upload(session, upload, entry_name)

    case upload_result do
      # A progress callback that navigates returns its redirect, which
      # commits like any other render result.
      {:error, entry_errors} when not is_tuple(entry_errors) ->
        {:halt, {:entry_error, session}}

      _result ->
        state = Session.page_state(session)

        # The caller prunes once the uploads end: the view still has to consume
        # an upload whose own progress removed its input.
        case commit_render_result(session, state.client_dom, upload_result, & &1) do
          %Session{} = session -> {:cont, {:ok, session}}
          navigation -> {:halt, {:navigation, navigation}}
        end
    end
  end

  defp upload_entry_names(upload), do: Enum.map(upload.entries, &Map.fetch!(&1, "name"))
  defp entry_names(entries), do: Enum.map(entries, & &1.name)

  defp prune_stale_live_uploads(%Session{} = session) do
    state = Session.page_state(session)

    {live_uploads, stale_uploads} =
      UploadState.prune(state.live_uploads, fn upload_state ->
        DocumentIndex.identity_present?(ClientDOM.index(state.client_dom), upload_state.input_identity) or
          UploadState.uploaded?(upload_state)
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
