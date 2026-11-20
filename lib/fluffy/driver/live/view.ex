defmodule Fluffy.Driver.Live.View do
  @moduledoc false

  # The Live driver's calls to the view, and what they found: how the view left (a
  # redirect it left or its exit), the patches it pushed, and how a render commits. Also
  # the view that owns an element. See `Fluffy.Driver.Live.ActionScope` for the rules a
  # call that sends the view something keeps.

  import Fluffy.Driver.Phoenix.HTML.Semantics, only: [attribute: 2]
  import Phoenix.LiveViewTest, except: [open_browser: 1, open_browser: 2]

  alias Fluffy.Driver.Live.ActionScope
  alias Fluffy.Driver.Live.Document
  alias Fluffy.Driver.Live.Event
  alias Fluffy.Driver.Live.State
  alias Fluffy.Driver.Phoenix.ClientDOM
  alias Fluffy.Driver.Phoenix.HTML.DocumentIndex
  alias Fluffy.Internal.Navigation
  alias Fluffy.Locator
  alias Fluffy.Session

  @retry_interval 10

  def node_identity(client_dom, target), do: Map.fetch!(ClientDOM.index(client_dom).nodes_by_id, target.id).identity

  # A patch keeps a node's identity but can move or remove the node, so a step
  # that follows it goes on only if this finds the node.
  def find_by_identity(client_dom, identity) do
    index = ClientDOM.index(client_dom)

    case Enum.find(index.entries, &(&1.identity == identity)) do
      nil -> nil
      entry -> DocumentIndex.target_by_id(index, entry.id)
    end
  end

  # Follows the redirect a view left when a call to it exited. An exit the
  # view left no redirect for raises a LiveViewError, or exits again when
  # `unexplained` is `:exit`.
  def follow_exit_redirect(session, reason, unexplained \\ :raise) do
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
  # exit.
  defp left_view(session), do: left_view_event(Session.page_state(session), @retry_interval)

  # A redirect an event causes comes back as the event call's result, and each
  # call that sends the view an event records that it reached the view for the
  # running action. The call fails only when it finds the view already gone, so
  # the event never reached it: follow the redirect the view left instead.
  def dispatch_view_event(session, dispatch) do
    case call_view(session, dispatch) do
      {:ok, result} -> result
      redirected -> redirected
    end
  end

  # render_upload can deliver a chunk and then exit on the view's redirect, so
  # once it starts, the view may have seen the action. Read the view before the
  # action first reaches it, so a view that already navigated away counts as
  # never having seen it. Later uploads follow a delivery and need no read.
  def dispatch_view_upload(session, upload, entry_name) do
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
  def read_view(session, read) do
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

  def redirected(session, redirect) do
    {:navigate, session, navigation} = follow_redirect_result(session, {:error, redirect})
    {:redirected, session, navigation}
  end

  def apply_last_patch(session) do
    case last_patch(Session.page_state(session).view) do
      nil -> session
      destination -> commit_patch(session, destination)
    end
  end

  def last_patch(%{proxy: {reference, topic, _proxy_pid}} = view, last \\ nil) do
    receive do
      {^reference, {:patch, ^topic, %{to: destination}}} -> last_patch(view, destination)
    after
      0 -> last
    end
  end

  # A patch keeps the document; only its URL changes.
  def commit_patch(session, destination) do
    url = Session.current_page(session).url |> URI.merge(destination) |> URI.to_string()
    Session.commit_page(session, :live, Session.page_state(session), url, same_document: true)
  end

  # Reports how the view left: the redirect its client handed Fluffy, or its
  # exit, waiting up to `wait` for the exit.
  def left_view_event(state, wait) do
    case current_redirect(state.view) do
      {:error, redirect} -> {:redirect, redirect}
      nil -> live_view_event(state.monitor, wait)
    end
  end

  defp live_view_event(monitor, wait) do
    tag = State.down_tag()

    receive do
      {^tag, ^monitor, :process, _pid, reason} = message ->
        leave_unread(message)
        view_exit(reason)
    after
      wait -> :none
    end
  end

  def view_exit({:shutdown, {kind, _options} = redirect}) when kind in [:redirect, :live_redirect],
    do: {:redirect, redirect}

  def view_exit(reason), do: {:died, reason}

  # A view leaves once, and that stays true until the session leaves its page,
  # so reading how it left leaves the message for the session's next call. A
  # call that fails before following it then needs no undo.
  def leave_unread(message), do: send(self(), message)

  def commit_render_result(session, _client_dom, {:error, {_kind, _options}} = redirect, _after_render) do
    follow_redirect_result(session, redirect)
  end

  def commit_render_result(_session, _client_dom, {:redirected, %Session{}, _nav} = redirected, _after_render) do
    redirected
  end

  # LiveViewTest answers nil when the event's nested view was removed before its
  # reply; the page is still whatever the root view renders now.
  def commit_render_result(session, client_dom, result, after_render) when is_binary(result) or is_nil(result) do
    render_view(session, client_dom, after_render)
  end

  # Renders the view, after an event or for a render the server pushed, and
  # commits the render. LiveView's client submits a form with phx-trigger-action
  # after any patch, so a triggered form navigates like a redirect the view left.
  # A patch arriving just after the render can put the URL a patch ahead.
  def render_view(session, client_dom, after_render) do
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
        session = apply_last_patch(session)
        state = %{Session.page_state(session) | client_dom: ClientDOM.reconcile(client_dom, document)}
        session = session |> Session.put_page_state(state) |> after_render.()

        case ClientDOM.triggered_submission(state.client_dom) do
          nil -> session
          submission -> {:navigate, session, Navigation.submission(submission, triggered: true)}
        end

      {:error, redirect} ->
        follow_redirect_result(session, {:error, redirect})

      {:exit, reason} ->
        follow_exit_redirect(session, reason)
    end
  end

  def follow_redirect_result(session, {:error, {_kind, %{to: destination} = options}}) do
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

  # Resolves the view a target's bindings reach, like the LiveView client's
  # owner lookup. Teleported portal content belongs to the view that owns the
  # portal, and elements outside every LiveView fall back to the main view.
  # `root_id` is the container that LiveViewTest selectors are relative to; it
  # is nil when element/2 cannot reach the target. Finding a nested view reads
  # the view's children, so a view that navigated away reports its redirect.
  def owning_view_context(session, target) do
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
            capability: :live_document,
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
  def find_view(%{id: id} = view, id), do: {:ok, view}

  def find_view(view, id) do
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

  # LiveViewTest's element form events fill in the form as the server rendered
  # it, which brings back a checkbox the user unchecked or an option they
  # deselected. Push the browser's serialization instead, with the form's
  # phx-value-* attributes winning over fields, as the LiveView client does.
  def render_view_event(client_dom, context, selector, kind, payload) do
    target = ClientDOM.target!(client_dom, Locator.by_css(selector))
    form = if target.tag == "form", do: target, else: DocumentIndex.form_owner(ClientDOM.index(client_dom), target)
    form_values = if form, do: Event.values(form.attributes), else: %{}

    Event.push(context.view, target, kind, Map.merge(payload, form_values))
  end

  def selector_for_view(client_dom, selector, %{root_id: root_id}) do
    root_selector = ClientDOM.selector_for_node_id(client_dom, root_id)

    case String.replace_prefix(selector, root_selector <> " > ", "") do
      ^selector ->
        raise Fluffy.LiveViewError,
          reason: {:target_outside_nested_live_view, selector, root_selector}

      relative_selector ->
        relative_selector
    end
  end
end
