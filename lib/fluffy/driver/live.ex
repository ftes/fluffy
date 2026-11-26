defmodule Fluffy.Driver.Live do
  @moduledoc false

  @behaviour Fluffy.Driver.Contract

  import Fluffy.Driver.Phoenix.HTML.Semantics, only: [attribute: 2]
  import Phoenix.LiveViewTest, except: [open_browser: 1, open_browser: 2]

  alias Fluffy.Deadline
  alias Fluffy.Driver.Live.ActionResolver
  alias Fluffy.Driver.Live.ActionScope
  alias Fluffy.Driver.Live.Document
  alias Fluffy.Driver.Live.Event
  alias Fluffy.Driver.Live.Processes
  alias Fluffy.Driver.Live.Retry
  alias Fluffy.Driver.Live.State
  alias Fluffy.Driver.Live.Upload
  alias Fluffy.Driver.Live.UploadState
  alias Fluffy.Driver.Live.View
  alias Fluffy.Driver.Phoenix.ClientDOM
  alias Fluffy.Driver.Phoenix.Form
  alias Fluffy.Driver.Phoenix.HTML.DocumentIndex
  alias Fluffy.Driver.Phoenix.HTML.Semantics
  alias Fluffy.Driver.Phoenix.HTML.Target
  alias Fluffy.Expect
  alias Fluffy.Internal.Navigation
  alias Fluffy.Internal.Navigation.Redirect
  alias Fluffy.Internal.Navigation.Submission
  alias Fluffy.Locator
  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.Timeouts
  # StringUtils is internal to Playwright, which is pinned.
  alias Playwright.Isomorphic.StringUtils

  @impl true
  def open_browser(%Session{} = session, open_fun) do
    endpoint = Session.context(session).http.endpoint
    Fluffy.OpenBrowser.write(document(session), Fluffy.OpenBrowser.static_asset_resolver(endpoint), open_fun)
    session
  end

  @impl true
  def validate_operation!(session, operation, arguments),
    do: Fluffy.Driver.Phoenix.Validation.validate_operation!(session, operation, arguments)

  @impl true
  def expect(%Session{} = session, %Expect{} = expectation) do
    deadline =
      expectation.options
      |> Timeouts.get(&Timeouts.phoenix/0)
      |> Retry.deadline()

    result =
      eventually(session, deadline, fn session ->
        case evaluate_expectation(session, expectation) do
          {:ok, passed?, _actual} when passed? != expectation.negated? ->
            {:ok, session}

          {:ok, _passed?, actual} ->
            {:retry, Expect.Internal.failure_message(expectation, actual)}
        end
      end)

    # An expectation goes on on the page a navigation landed on, like an
    # action, so pages that keep navigating fail it at the redirect limit.
    case result do
      {:redirected, session, navigation} ->
        retry_on_new_page(session, navigation, :expect, [expectation], deadline)

      session ->
        session
    end
  end

  @impl true
  def click(%Session{} = session, %Locator{} = locator, action_options \\ []) do
    act(session, :click, [locator, action_options], fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &ClientDOM.click(&1, locator, :live)) do
        {%Session{} = session, click} -> commit_user_click(session, click)
        navigation -> navigation
      end
    end)
  end

  # A browser runs a click's handlers and default action at once, before any
  # reply: a click that toggles a checkbox or selects a radio fires input and
  # change after the click event, and a label's click clicks its control. So
  # the events the clicks send, phx-click and then phx-change, and the last
  # click's default action are settled from the pages the clicks left, before
  # any is sent, and pushed in order, each reply committing on the page the
  # last one left. A view found gone meanwhile navigated before the click.
  defp commit_user_click(session, {clicks, default}) do
    with {:ok, clicked_dom, steps} <- prepare_clicks(session, clicks, default, []) do
      run_steps(session, clicked_dom, steps)
    end
  end

  # Phoenix.HTML's handler takes the click before LiveView's client.
  defp prepare_clicks(session, [{target, client_dom, _client_dom}], {:phoenix_html, submission}, _pending) do
    with {:ok, _event_context} <- View.owning_view_context(session, target) do
      if competing_live_click_binding?(target) do
        raise Fluffy.CapabilityError,
          capability: :phoenix_html_actions,
          driver: :live,
          detail:
            "a data-method/data-to link with a competing phx-click or LiveView navigation action requires Playwright"
      end

      {:ok, client_dom, [&{:navigate, &1, Navigation.submission(submission)}]}
    end
  end

  # Each click event reaches its binding before the click's default action
  # takes place. LiveView's client skips a `pending` binding, which still
  # awaits the reply to its push or live patch (PHX_REF_SRC), and prevents
  # the default for a LiveView link or href="#", which the browser then
  # reverts: it undoes the click's toggle, fires no change and goes no
  # further. Otherwise a toggled control fires change, a label's click clicks
  # its control, and the last click submits its form or follows its link, all
  # before the server replies.
  defp prepare_clicks(session, [{target, client_dom, clicked_dom} | clicks], default, pending) do
    with {:ok, event_context} <- View.owning_view_context(session, target) do
      binding = click_binding(clicked_dom, target)
      binding = if binding && View.node_identity(clicked_dom, binding) not in pending, do: binding
      commands = if binding, do: Event.click_commands(binding.attributes), else: []
      click = binding_step(clicked_dom, binding, commands, event_context)

      if binding && prevents_default?(binding) do
        {:ok, client_dom, List.wrap(click)}
      else
        change = if clicked_dom != client_dom, do: change_step(clicked_dom, target, event_context)

        pending =
          if command?(commands, ~w(push patch)), do: [View.node_identity(clicked_dom, binding) | pending], else: pending

        rest =
          if clicks == [],
            do: {:ok, clicked_dom, default_steps(session, clicked_dom, default, event_context)},
            else: prepare_clicks(session, clicks, default, pending)

        with {:ok, final_dom, steps} <- rest, do: {:ok, final_dom, Enum.reject([click, change | steps], &is_nil/1)}
      end
    end
  end

  defp run_steps(session, clicked_dom, steps) do
    state = Session.page_state(session)

    Enum.reduce_while(steps, Session.put_page_state(session, %{state | client_dom: clicked_dom}), fn step, session ->
      case step.(session) do
        %Session{} = session -> {:cont, session}
        navigation -> {:halt, navigation}
      end
    end)
  end

  defp competing_live_click_binding?(target) do
    Enum.any?([target | Enum.reverse(target.ancestors)], fn element ->
      not is_nil(attribute(element.attributes, "phx-click")) or
        not is_nil(attribute(element.attributes, "data-phx-link"))
    end)
  end

  # The click's phx-click, with the payload the click found. Like the LiveView
  # client, a push, patch or navigate goes through the view, and
  # JS.dispatch("change") fires a change event on the element so its form
  # sends phx-change. Other commands send the view nothing.
  defp binding_step(client_dom, binding, commands, event_context) do
    cond do
      command?(commands, ~w(navigate patch push)) ->
        payload = Event.element_values(client_dom, binding)

        fn session ->
          result = View.dispatch_view_event(session, fn -> Event.push(event_context.view, binding, :click, payload) end)
          commit_render_result(session, Session.page_state(session).client_dom, result)
        end

      Enum.any?(commands, &match?(["dispatch", %{"event" => "change"}], &1)) ->
        event = ClientDOM.dispatch_change_event(client_dom, binding)
        &push_found_change(&1, client_dom, event, event_context)

      true ->
        nil
    end
  end

  defp command?(commands, names), do: Enum.any?(commands, fn [name, _options] -> name in names end)

  # The change goes as the click left the form, which the click's reply may
  # reset, and a selector such as :checked stops matching after uncheck. So
  # follow the control across the replies, and find the view that owns it
  # there, since a reply may have moved it. A control a reply removed changes
  # where the click found it, as the browser sent its change before the reply.
  defp change_step(client_dom, target, event_context) do
    identity = View.node_identity(client_dom, target)

    with %{} = sent <- ClientDOM.change_event(client_dom, target) do
      fn session ->
        clicked_dom = Session.page_state(session).client_dom

        case View.find_by_identity(clicked_dom, identity) do
          %Target{} = clicked ->
            dispatch_live_change(session, clicked_dom, clicked, sent)

          nil ->
            push_removed_change(session, client_dom, sent, event_context)
        end
      end
    end
  end

  # A nested view the reply removed with the control gets nothing.
  defp push_removed_change(session, client_dom, sent, event_context) do
    state = Session.page_state(session)

    case View.read_view(session, fn -> with {:ok, view} <- View.find_view(state.view, event_context.view.id), do: view end) do
      {:ok, nil} -> session
      {:ok, _view} -> push_found_change(session, client_dom, sent, event_context)
      redirected -> redirected
    end
  end

  # LiveView's client prevents a click's default action for a LiveView link,
  # whose handler stops the event, and for an href="#" binding.
  defp prevents_default?(binding), do: live_link?(binding) or attribute(binding.attributes, "href") == "#"

  # Like the LiveView client's closestPhxBinding, a click goes to the closest
  # element with phx-click that is not disabled, up to its LiveView's container.
  # The closest LiveView link wins over any phx-click: its handler stops the
  # event and prevents the default action.
  defp click_binding(client_dom, target) do
    closest_binding(client_dom, target, "data-phx-link") || closest_binding(client_dom, target, "phx-click")
  end

  defp closest_binding(client_dom, target, name) do
    boundary? = &(&1.id != target.id and attribute(&1.attributes, "data-phx-session") != nil)
    bound? = &(attribute(&1.attributes, name) != nil and not disabled_control?(&1))

    case ClientDOM.closest(client_dom, target, &(boundary?.(&1) or bound?.(&1))) do
      nil -> nil
      element -> if boundary?.(element), do: nil, else: element
    end
  end

  defp live_link?(element), do: attribute(element.attributes, "data-phx-link") != nil

  defp disabled_control?(element) do
    element.tag in ~w(button fieldset input optgroup option select textarea) and
      List.keymember?(element.attributes, "disabled", 0)
  end

  # The steps that take the last click's default action on a session.
  defp default_steps(session, client_dom, default, event_context) do
    case default do
      nil ->
        []

      {:link, %{attributes: attributes}} ->
        navigation = Navigation.link(attribute(attributes, "href"), download: attribute(attributes, "download"))
        [&{:navigate, &1, navigation}]

      {:submit, submitter, %{phx_submit?: true} = submission} ->
        case Upload.live_upload_for_submit(session, submitter) do
          {:ok, form_id, upload} -> [&Upload.dispatch_live_upload_submit(&1, form_id, upload, submission)]
          :none -> [live_submit(client_dom, submission, event_context)]
        end

      {:submit, _submitter, %{phx_submit?: false} = submission} ->
        navigation = Navigation.submission(submission)
        [&{:navigate, &1, navigation}]
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

    with {:ok, event_context} <- View.owning_view_context(session, target) do
      case ClientDOM.submit_form(client_dom, target, :live) do
        nil ->
          raise ArgumentError, "Fluffy.submit/3: requires a form locator, got #{inspect(target.tag)}"

        %{phx_submit?: true} = submission ->
          live_submit(client_dom, submission, event_context).(session)

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
          Upload.set_live_upload(session, locator, selected_files)

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

  @doc """
  The state of a page with the LiveView `view` the backend mounted, which rendered
  `html`, and the redirect the view reported right after mounting, if any. The view and
  its client proxy stop with the session, or with `release/2`.
  """
  def mount(runtime, view, html) do
    # LiveViewTest links its client proxy to the test process, and the proxy
    # exits with the view's reason. Unlink it so a view that redirects or
    # crashes doesn't take the test down; the view's monitor reports how it left,
    # and the proxy's why the view closed when the proxy crashed first.
    proxy_pid = proxy_pid(view)
    Process.unlink(proxy_pid)

    monitor = State.monitor(view.pid)
    client_monitor = State.monitor(proxy_pid)

    :ok = Processes.register(runtime, :live_view, view.pid)
    :ok = Processes.register(runtime, :live_view, proxy_pid)

    document = Document.new(html, view.id)

    # The view can redirect or exit right after mounting. Its mounted document
    # stands then: the backend follows a reported redirect, and an exit is left to
    # the driver's next read.
    {client_dom, redirect} =
      try do
        case Document.render(document, view) do
          {:ok, composed} -> {ClientDOM.from_document(composed, Document.doctype()), nil}
          {:error, redirect} -> {mounted_client_dom(html), redirect}
        end
      catch
        :exit, _reason -> {mounted_client_dom(html), nil}
      end

    state = %State{
      client_dom: client_dom,
      document: document,
      live_uploads: UploadState.new(),
      view: view,
      monitor: monitor,
      client_monitor: client_monitor
    }

    {state, redirect}
  end

  defp mounted_client_dom(html), do: html |> LazyHTML.from_document() |> ClientDOM.from_document(Document.doctype())

  @doc "Stops the LiveView of a page whose document the backend replaces, with its upload clients."
  def release(%Session{} = session, %Page.State{driver: :live, state: state}) do
    state.live_uploads |> UploadState.forms() |> Enum.each(&Upload.release_live_upload_clients(session, &1))

    proxy_pid = proxy_pid(state.view)
    Process.demonitor(state.monitor, [:flush])
    Process.demonitor(state.client_monitor, [:flush])
    Processes.stop(state.view.pid, :normal)
    Processes.stop(proxy_pid, :normal)
    Processes.release(session.runtime, :live_view, state.view.pid)
    Processes.release(session.runtime, :live_view, proxy_pid)
    flush_view_messages(state.view)
    :ok
  end

  defp flush_view_messages(%{proxy: {reference, _topic, _proxy_pid}} = view) do
    receive do
      {^reference, _message} -> flush_view_messages(view)
    after
      0 -> :ok
    end
  end

  defp proxy_pid(%{proxy: {_reference, _topic, proxy_pid}}) when is_pid(proxy_pid), do: proxy_pid

  @impl true
  def set_checked(%Session{} = session, %Locator{} = locator, desired, options \\ []) do
    act(session, :set_checked, [locator, desired, options], fn session, deadline ->
      case resolve_live_action(session, locator, deadline, &ClientDOM.set_checked(&1, locator, desired, :live)) do
        {%Session{} = session, nil} ->
          session

        {%Session{} = session, {click, control}} ->
          commit_set_checked(session, click, control, desired, locator)

        navigation ->
          navigation
      end
    end)
  end

  # Like Playwright, check the control's state once the click's events went,
  # on the page the click left, as a browser's check runs before any reply.
  defp commit_set_checked(session, {clicks, default}, control, desired, locator) do
    with {:ok, clicked_dom, steps} <- prepare_clicks(session, clicks, default, []) do
      committed = run_steps(session, clicked_dom, steps)
      ClientDOM.ensure_checked!(clicked_dom, control, desired, locator)
      committed
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
  # first phase meets the document the target was found in. A Phoenix press
  # types nothing, so both phases carry the value the element had then. An
  # element without either binding gets the keydown, which raises.
  defp dispatch_keys(session, target, key) do
    phases = Enum.filter([:keydown, :keyup], &key_binding?(target, &1))
    [first | rest] = if phases == [], do: [:keydown], else: phases
    # As in LiveView's client, phx-value-key wins over the pressed key.
    payload = Map.merge(%{"key" => key}, Event.element_values(Session.page_state(session).client_dom, target))

    with {:ok, context} <- View.owning_view_context(session, target),
         %Session{} = session <- dispatch_key(session, context, target, payload, first) do
      if rest == [], do: session, else: dispatch_bound_keyup(session, context, target, payload)
    end
  end

  defp key_binding?(target, phase) do
    attribute(target.attributes, "phx-#{phase}") != nil or
      attribute(target.attributes, "phx-window-#{phase}") != nil
  end

  defp dispatch_key(session, context, target, payload, phase) do
    result = View.dispatch_view_event(session, fn -> Event.push(context.view, target, phase, payload) end)
    commit_render_result(session, Session.page_state(session).client_dom, result)
  end

  defp dispatch_bound_keyup(session, context, target, payload) do
    state = Session.page_state(session)

    case View.read_view(session, fn -> with {:ok, view} <- View.find_view(state.view, context.view.id), do: view end) do
      # The keydown removed the nested view that owns the target.
      {:ok, nil} ->
        session

      {:ok, view} ->
        dispatch_key(session, %{context | view: view}, target, payload, :keyup)

      redirected ->
        redirected
    end
  end

  @impl true
  def text_content(%Session{} = session, %Locator{} = locator, options \\ []),
    do: read(session, :text_content, [locator, options], &ClientDOM.text_content(&1, locator))

  @impl true
  def all_text_contents(%Session{} = session, %Locator{} = locator, options \\ []),
    do: read(session, :all_text_contents, [locator, options], &ClientDOM.all_text_contents(&1, locator))

  @impl true
  def get_attribute(%Session{} = session, %Locator{} = locator, name, options \\ []),
    do: read(session, :get_attribute, [locator, name, options], &ClientDOM.get_attribute(&1, locator, name))

  @impl true
  def input_value(%Session{} = session, %Locator{} = locator, options \\ []),
    do: read(session, :input_value, [locator, options], &ClientDOM.input_value(&1, locator))

  @impl true
  def all(%Session{} = session, %Locator{} = locator, options \\ []),
    do: read(session, :all, [locator, options], &length(ClientDOM.resolve(&1, locator)))

  @impl true
  def content(%Session{} = session, options \\ []), do: page_read(session, :content, options, &ClientDOM.content/1)

  @impl true
  def title(%Session{} = session, options \\ []), do: page_read(session, :title, options, &ClientDOM.title/1)

  # As in Playwright, a wait retries on fresh renders until its target reaches its state,
  # as an expectation does, and goes on on the page a navigation it finds lands on.
  @impl true
  def wait_for(%Session{} = session, %Locator{} = locator, options \\ []) do
    deadline = options |> Timeouts.get(&Timeouts.phoenix/0) |> Retry.deadline()
    wait = &ClientDOM.wait_for(&1, locator, Keyword.fetch!(options, :state))

    case eventually(session, deadline, &ActionResolver.attempt(&1, locator, wait)) do
      {:redirected, session, navigation} ->
        retry_on_new_page(session, navigation, :wait_for, [locator, options], deadline)

      {%Session{} = session, :ok} ->
        session
    end
  end

  # As in Playwright, a read waits for its target to attach, on fresh renders as an
  # expectation does, and returns the value it first reads. A navigation it finds sends
  # it on to the new page, within its timeout. A read that finds no target, such as
  # `all_text_contents`, reads once.
  defp read(session, operation, [locator | _rest] = arguments, read) do
    deadline =
      arguments
      |> List.last()
      |> Timeouts.get(&Timeouts.phoenix/0)
      |> Retry.deadline()

    case eventually(session, deadline, &ActionResolver.attempt(&1, locator, read)) do
      {:redirected, session, navigation} -> retry_on_new_page(session, navigation, operation, arguments, deadline)
      {%Session{} = session, value} -> {:return, value, session}
    end
  end

  # A page read reads the latest render once, on the page a navigation it finds lands on.
  # As in Playwright, it has no timeout.
  defp page_read(session, operation, options, read) do
    deadline = Retry.deadline(:infinity)

    case eventually(session, deadline, &{:ok, {&1, read.(client_dom(&1))}}) do
      {:redirected, session, navigation} -> retry_on_new_page(session, navigation, operation, [options], deadline)
      {%Session{} = session, value} -> {:return, value, session}
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

  defp evaluate_expectation(%Session{} = session, %Expect{target: :page, kind: :url, expected: expected}) do
    actual = Session.current_page(session).url
    {:ok, Expect.Internal.url_matches?(expected, Session.context(session).http.base_url, actual), actual}
  end

  defp evaluate_expectation(%Session{} = session, %Expect{} = expectation) do
    {passed?, actual} = ClientDOM.Expectation.evaluate(client_dom(session), expectation)

    actual =
      if expectation.kind == :visible and actual == 0, do: document_text(session), else: actual

    {:ok, passed?, actual}
  end

  defp client_dom(session), do: session |> Session.page_state() |> Map.fetch!(:client_dom)
  defp document(session), do: session |> client_dom() |> Map.fetch!(:document)

  # The page's text as Playwright reads it, without <template> content.
  defp document_text(session) do
    {:ok, root} = session |> client_dom() |> ClientDOM.index() |> DocumentIndex.fetch_by_id(0)
    root |> Semantics.text() |> StringUtils.normalize_white_space()
  end

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

  # A server-pushed render can drop upload entries, as an event's can.
  defp refresh(session) do
    View.render_view(session, Session.page_state(session).client_dom, &Upload.prune_stale_live_uploads/1)
  catch
    :exit, reason -> View.follow_exit_redirect(session, reason)
  end

  defp reconcile_unwrapped(session, client_dom) do
    state = Session.page_state(session)

    case View.left_view_event(state, 0) do
      {:redirect, redirect} ->
        View.follow_redirect_result(session, {:error, redirect})

      {:died, reason} ->
        raise Fluffy.LiveViewError, reason: reason

      :none ->
        # The render syncs with the view, so a patch the callback set off without
        # waiting has arrived when the result commits it.
        try do
          state.view |> render() |> then(&commit_render_result(session, client_dom, &1))
        catch
          :exit, reason -> View.follow_exit_redirect(session, reason, :exit)
        end
    end
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
    deadline =
      arguments
      |> List.last()
      |> Timeouts.get(&Timeouts.phoenix/0)
      |> Retry.deadline()

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
      {:retry_on_new_page, session, navigation} -> retry_on_new_page(session, navigation, operation, arguments, deadline)
      result -> result
    end
  end

  defp finish_action(result, delivered?, operation, arguments, deadline) do
    case {navigation_found(result), delivered?} do
      {{session, navigation}, true} ->
        {:navigate, session, navigation}

      {{session, navigation}, false} ->
        if Deadline.expired?(deadline), do: raise_navigated_away(operation, arguments, deadline)
        {:retry_on_new_page, session, navigation}

      {:none, _delivered?} ->
        result
    end
  end

  # A navigation an action or expectation found before reaching the view, a
  # redirect the view left or a form it triggered, goes back to the backend to
  # follow, with the retry to run on the new page. The navigation counts toward
  # the retry's timeout, and toward the redirect limit of the retries and of the
  # redirects it leads to (see docs/capabilities.md). An action whose following
  # used up its budget fails on the new page. The retry runs outside the action's
  # scope, as an action of its own on the page its `redirects`-th redirect landed
  # on, on that page's driver.
  defp retry_on_new_page(session, %struct{} = navigation, operation, arguments, deadline)
       when struct in [Redirect, Submission] do
    redirects = Navigation.count_redirect!(ActionScope.redirects(), URI.parse(Session.current_page(session).url))

    retry = fn session, dispatch ->
      if operation != :expect and Deadline.expired?(deadline), do: raise_navigated_away(operation, arguments, deadline)
      arguments = List.update_at(arguments, -1, &put_timeout(&1, Deadline.timeout(deadline)))
      ActionScope.after_redirects(redirects, fn -> dispatch.(session, operation, arguments) end)
    end

    {:navigate, session, %{navigation | redirects: redirects}, retry}
  end

  defp put_timeout(%Expect{} = expectation, timeout), do: Expect.Internal.merge_options(expectation, timeout: timeout)
  defp put_timeout(options, timeout), do: Keyword.put(options, :timeout, timeout)

  defp raise_navigated_away(operation, arguments, deadline) do
    [action: action_label(operation, arguments), reason: :navigated_away, locator: hd(arguments)]
    |> Fluffy.ActionabilityError.exception()
    |> Fluffy.TestTimeout.explain(deadline)
    |> raise()
  end

  defp action_label(:set_checked, [_locator, desired, _options]), do: if(desired, do: :check, else: :uncheck)
  defp action_label(operation, _arguments), do: operation

  # Checks the mailbox only: a view that left or patched reports it to Fluffy
  # right away. Returns the session on the patched document, if any, or the
  # redirect the view left.
  defp unread_navigation(session) do
    case View.left_view_event(Session.page_state(session), 0) do
      {:redirect, redirect} -> View.redirected(session, redirect)
      :none -> apply_unread_patches(session)
      {:died, reason} -> raise_after_patches(session, reason)
    end
  end

  # A patch is committed as it is taken, and the last one decides the URL. It
  # also changes what the view renders, so the action reads the view for the
  # patched document before it goes on.
  defp apply_unread_patches(session) do
    case View.last_patch(Session.page_state(session).view) do
      nil ->
        session

      destination ->
        case session |> View.commit_patch(destination) |> refresh() do
          %Session{} = session -> session
          {:navigate, session, navigation} -> {:redirected, session, navigation}
        end
    end
  end

  # An action keeps a patch the view pushed before it died, however soon its
  # exit arrived.
  defp raise_after_patches(session, reason) do
    View.apply_last_patch(session)
    raise Fluffy.LiveViewError, reason: reason
  end

  # A navigation the action found before it finished, whether a view call or
  # the wait for its target saw it.
  defp navigation_found({:redirected, session, navigation}), do: {session, navigation}
  defp navigation_found(_result), do: :none

  # A patch changes the document in place, so the wait commits it and goes on
  # there, while a redirect ends the wait on the new page. A committed patch
  # stays applied even if the action fails.
  defp wait_for_retry(session, wait) do
    state = Session.page_state(session)
    %{proxy: {reference, topic, _proxy_pid}} = state.view
    monitor = state.monitor
    tag = State.down_tag()

    receive do
      {^reference, {:patch, ^topic, %{to: destination}}} ->
        View.commit_patch(session, destination)

      {^tag, ^monitor, :process, _pid, reason} = message ->
        View.leave_unread(message)

        case View.view_exit(state, reason) do
          {:died, reason} -> raise Fluffy.LiveViewError, reason: reason
          {:redirect, redirect} -> View.follow_redirect_result(session, {:error, redirect})
        end
    after
      wait -> session
    end
  end

  # `sent`, a change event read earlier, gives the fields and `_target` to send
  # instead of `client_dom`'s; `client_dom` still locates its dispatcher.
  defp dispatch_live_change(session, client_dom, %Target{} = target, sent \\ nil) do
    with {:ok, event_context} <- View.owning_view_context(session, target) do
      event =
        case {ClientDOM.change_event(client_dom, target), sent} do
          {%{} = event, %{} = sent} -> %{event | fields: sent.fields, target_name: sent.target_name}
          {event, _sent} -> event
        end

      push_change_event(session, client_dom, event, event_context)
    end
  end

  # Like the LiveView client, `_target` is the input's name, or "undefined";
  # the channel decodes it into the path that handle_event sees.
  defp push_change_event(session, client_dom, event, event_context) do
    state = Session.page_state(session)

    session
    |> Session.put_page_state(%{state | client_dom: client_dom})
    |> push_found_change(client_dom, event, event_context)
  end

  # Pushes a change read from `client_dom`, where its dispatcher is found, and
  # commits the reply on the session's page.
  defp push_found_change(session, _client_dom, nil, _event_context), do: session

  defp push_found_change(session, client_dom, event, event_context) do
    payload = event.fields |> Form.to_params() |> Map.put("_target", event.target_name || "undefined")

    result =
      View.dispatch_view_event(session, fn ->
        View.render_view_event(client_dom, event_context, event.dispatcher_selector, :change, payload)
      end)

    commit_render_result(session, Session.page_state(session).client_dom, result)
  end

  # Like the LiveView client, a submit reads its form at once, even while a
  # click's phx-click awaits its reply. The returned function pushes it once
  # that reply has rendered, and marks the form used in what it rendered.
  defp live_submit(client_dom, submission, event_context) do
    form_key = View.node_identity(client_dom, %{id: submission.form_id})
    form_selector = ClientDOM.selector_for_node_id(client_dom, submission.form_id)
    payload = Form.to_params(submission.fields)
    push = fn -> View.render_view_event(client_dom, event_context, form_selector, :submit, payload) end

    fn session ->
      state = Session.page_state(session)

      rendered =
        case View.find_by_identity(state.client_dom, form_key) do
          nil -> state.client_dom
          form -> ClientDOM.mark_form_used(state.client_dom, form.id)
        end

      commit_render_result(session, rendered, View.dispatch_view_event(session, push))
    end
  end

  defp commit_render_result(session, client_dom, result),
    do: View.commit_render_result(session, client_dom, result, &Upload.prune_stale_live_uploads/1)
end
