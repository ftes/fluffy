defmodule Fluffy.Backend.Playwright do
  @moduledoc false

  @behaviour Fluffy.Backend.Contract

  alias Fluffy.Backend.Playwright.Context
  alias Fluffy.BrowserRuntime
  alias Fluffy.Deadline
  alias Fluffy.Dialog, as: DialogResult
  alias Fluffy.Download
  alias Fluffy.Driver.Playwright.State
  alias Fluffy.FailureArtifact
  alias Fluffy.FileChooser
  alias Fluffy.HTTPEvent
  alias Fluffy.Internal.Navigation.BrowserCommitted
  alias Fluffy.Internal.Navigation.BrowserPatch
  alias Fluffy.NavigationEvent
  alias Fluffy.Page
  alias Fluffy.PageLifecycle
  alias Fluffy.Playwright.Response
  alias Fluffy.Session
  alias PlaywrightEx.Browser
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Connection
  alias PlaywrightEx.Dialog, as: BrowserDialog
  alias PlaywrightEx.Download, as: BrowserDownload
  alias PlaywrightEx.EventWaiter
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.Tracing

  @impl true
  def start_session(options, attachment) do
    {resource_scope, runtime, sandbox_header} = attachment
    browser_id = BrowserRuntime.browser_id()
    %{playwright_supervisor: playwright_supervisor} = BrowserRuntime.status()
    connection = PlaywrightEx.Supervisor.connection_name(playwright_supervisor)

    browser_context_options = Keyword.get(options, :browser_context, [])

    browser_context_headers =
      browser_context_options
      |> Keyword.get(:extra_http_headers, %{})
      |> Map.to_list()

    headers =
      (browser_context_headers ++ Keyword.get(options, :headers, []))
      |> deduplicate_headers()
      |> put_header(sandbox_header)
      |> Enum.map(fn {name, value} -> %{name: to_string(name), value: to_string(value)} end)

    base_url = Keyword.fetch!(options, :base_url)

    context_options =
      browser_context_options
      |> Keyword.delete(:extra_http_headers)
      |> normalize_browser_context_options()
      |> Keyword.put_new(:locale, "en")
      |> Keyword.put(:base_url, base_url)
      # playwright_ex 0.8 does not special-case this protocol acronym when
      # camelizing `:extra_http_headers`, so use the exact wire key.
      |> Keyword.put(:extraHTTPHeaders, headers)
      |> Keyword.put(:connection, connection)
      |> Keyword.put(:timeout, timeout())

    {:ok, context} =
      Browser.new_context(browser_id, context_options)

    cleanup_timeout = Keyword.get(options, :timeout, timeout())

    :ok =
      Fluffy.SessionRuntime.register(runtime, {:browser_context, connection, context.guid}, fn ->
        BrowserContext.close(context.guid, connection: connection, timeout: cleanup_timeout)
      end)

    {:ok, browser_page} =
      BrowserContext.new_page(context.guid, connection: connection, timeout: timeout())

    subscribe_to_console!(browser_page.guid, connection)

    context_state = %Context{
      connection: connection,
      context_id: context.guid,
      tracing_id: context.tracing.guid,
      base_url: base_url,
      resource_scope: resource_scope,
      timeout: Keyword.get(options, :timeout, timeout())
    }

    page_state =
      new_page_state(
        context.guid,
        browser_page.guid,
        browser_page.main_frame.guid
      )

    page = %Page.State{name: :main, driver: :playwright, state: page_state}

    session = Session.new(__MODULE__, context_state, page, runtime)
    :ok = Fluffy.SessionRuntime.monitor(runtime, GenServer.whereis(connection))
    :ok = Connection.subscribe_sync(connection, runtime, context.guid)
    session
  end

  @impl true
  def page_snapshot(context, page) do
    case Frame.snapshot(page.state.frame_id, connection: context.connection) do
      {:ok, snapshot} -> %{page | url: snapshot.url, document_id: {snapshot.document_ref, page.document_id}}
      {:error, _error} -> raise ArgumentError, "page #{inspect(page.name || page.id)} is closed"
    end
  end

  @impl true
  def page_status(context, page) do
    case Response.for_document(page.state.frame_id, connection: context.connection, timeout: context.timeout) do
      {:ok, %{status: status}} -> status
      {:ok, nil} -> nil
      {:error, error} -> raise ArgumentError, "cannot read page status: #{inspect(error)}"
    end
  end

  @impl true
  def commit_page(page, driver, state, _url, options) do
    options = Keyword.validate!(options, same_document: false, live_redirect: false)

    # The browser owns document identity. Only LiveView redirects need a local
    # identity because they replace the view inside the same HTML document.
    document_id =
      cond do
        options[:same_document] -> page.document_id
        options[:live_redirect] -> make_ref()
        true -> nil
      end

    %{page | driver: driver, state: state, url: nil, document_id: document_id}
  end

  @impl true
  def prepare_page(context, page, runtime) do
    id = page.state.page_id
    Connection.subscribe(context.connection, runtime, id)
    opener = Connection.initializer!(context.connection, id)[:opener]
    opener_id = if opener, do: opener.guid
    {:ok, {%{page | url: nil, document_id: nil}, id, opener_id}}
  rescue
    ArgumentError -> {:error, "page #{inspect(page.name || page.id)} is closed"}
  end

  @impl true
  def runtime_event(context, {:playwright_msg, %{method: :page, params: %{page: %{guid: guid}}}}) do
    # Read cached metadata only; page readiness remains in the action caller.
    initializer = Connection.initializer!(context.connection, guid)

    page = %Page.State{
      driver: :playwright,
      state: %State{context_id: context.context_id, page_id: guid, frame_id: initializer.main_frame.guid}
    }

    case prepare_page(context, page, self()) do
      {:ok, registration} -> {:page_opened, registration}
      {:error, _} -> :ignore
    end
  rescue
    # A page may be disposed before its creation event reaches the runtime.
    ArgumentError -> :ignore
  end

  def runtime_event(%{context_id: guid}, {:playwright_msg, %{method: method, guid: guid}})
      when method in [:close, :__dispose__], do: :closed

  def runtime_event(_context, {:playwright_msg, %{method: method, guid: guid}}) when method in [:close, :__dispose__],
    do: {:page_closed, guid}

  def runtime_event(_context, _message), do: :ignore

  @impl true
  def run_step(session, name, location, fun) do
    context = Session.context(session)

    if context.trace do
      Tracing.group(
        context.tracing_id,
        [connection: context.connection, timeout: context.timeout, name: name, location: location],
        fun
      )
    else
      fun.()
    end
  end

  @impl true
  def capture_failure(%Session{} = session, operation, error, stacktrace) do
    FailureArtifact.capture(session, operation, error, stacktrace)
  end

  @impl true
  def normalize_error(_session, _operation, _arguments, error), do: error

  @impl true
  def absolute_url(%Session{} = session, path) do
    Session.context(session).base_url |> URI.merge(path) |> URI.to_string()
  end

  @impl true
  def visit(%Session{} = session, path) do
    state = Session.page_state(session)
    navigation_timeout = Session.context(session).timeout

    case Frame.goto(state.frame_id,
           url: path,
           wait_until: "load",
           timeout: navigation_timeout
         ) do
      {:ok, _response} ->
        adopt_navigated_document(session, state, nil, navigation_timeout)

      {:error, error} ->
        raise "Playwright navigation failed: #{inspect(error)}"
    end
  end

  @impl true
  def reload(%Session{} = session, options \\ []) do
    options = Keyword.validate!(options, [:timeout])
    state = Session.page_state(session)
    reload_timeout = options |> Keyword.get(:timeout, Session.context(session).timeout) |> max(1)

    case BrowserPage.reload(state.page_id,
           connection: Session.context(session).connection,
           timeout: reload_timeout
         ) do
      {:ok, _response} ->
        adopt_navigated_document(session, state, nil, reload_timeout)

      {:error, error} ->
        raise "Playwright reload failed: #{inspect(error)}"
    end
  end

  @impl true
  def navigate(%Session{} = session, %BrowserCommitted{
        state: state,
        url: url,
        live_navigation_cursor: live_navigation_cursor
      }) do
    navigation_timeout = Session.context(session).timeout

    adopt_navigated_document(
      session,
      state,
      url,
      navigation_timeout,
      live_navigation_cursor
    )
  end

  def navigate(%Session{} = session, %BrowserPatch{state: state, url: url}) do
    Session.commit_page(session, :playwright, state, url, same_document: true)
  end

  @impl true
  def new_page(session, name) do
    if Map.has_key?(Session.pages(session), name),
      do: raise(ArgumentError, "page name #{inspect(name)} is already in use")

    context = Session.context(session)

    {:ok, browser_page} =
      BrowserContext.new_page(context.context_id, connection: context.connection, timeout: context.timeout)

    subscribe_to_console!(browser_page.guid, context.connection)
    state = new_page_state(context.context_id, browser_page.guid, browser_page.main_frame.guid)
    {:ok, snapshot} = Frame.snapshot(state.frame_id, connection: context.connection)
    state = %{state | document_identity: snapshot.document_ref}
    page = %Page.State{name: name, driver: :playwright, state: state}
    session |> Session.put_page(page) |> Session.activate_page(name)
  end

  @impl true
  def history(session, direction, options) do
    previous_url = Session.current_page(session).url
    state = Session.page_state(session)
    timeout = max(Keyword.get(options, :timeout, Session.context(session).timeout), 1)

    result =
      Connection.send(
        Session.context(session).connection,
        %{guid: state.page_id, method: direction, params: %{wait_until: "load", timeout: timeout}},
        timeout
      )

    case PlaywrightEx.ChannelResponse.unwrap(result, & &1) do
      {:ok, _response} ->
        {:ok, snapshot} = Frame.snapshot(state.frame_id, connection: Session.context(session).connection)

        if snapshot.url == previous_url and snapshot.document_ref == state.document_identity do
          session
        else
          adopt_navigated_document(session, state, nil, timeout)
        end

      {:error, error} ->
        raise "Playwright #{direction} failed: #{inspect(error)}"
    end
  end

  @impl true
  def close_page(%Session{} = session, page_id) do
    PageLifecycle.close_page(session, page_id, &release_page/3)
  end

  @impl true
  def arm_event(%Session{} = session, :download, options) do
    # The protocol decoder uses existing atoms for download metadata keys.
    Code.ensure_loaded!(BrowserDownload)

    {:ok, waiter} =
      BrowserPage.expect_download(Session.page_state(session).page_id,
        connection: Session.context(session).connection,
        timeout: Keyword.fetch!(options, :timeout),
        predicate: &Download.matches?(&1.suggested_filename, &1.url, options)
      )

    {:ok, session, %{type: :download, waiter: waiter, options: options}}
  end

  def arm_event(%Session{} = session, :navigation, options) do
    state = Session.page_state(session)
    from_url = Session.current_page(session).url
    from_status = Page.status(Session.handle(session))

    predicate = fn %{params: params} ->
      not is_binary(params[:error]) and (Map.has_key?(params, :new_document) or params.url != from_url)
    end

    transform = fn %{params: params} ->
      with {:ok, status} <- navigation_status(session, from_status, params) do
        {:ok, %NavigationEvent{from_url: from_url, url: params.url, status: status}}
      end
    end

    arm_waiter(session, :navigation, state.frame_id, :navigated, options, predicate: predicate, transform: transform)
  end

  def arm_event(%Session{} = session, type, options) when type in [:page, :popup] do
    name =
      case Fluffy.SessionRuntime.pending_capture(session.runtime) do
        {:ok, %{key: name}} -> name
        {:error, message} -> raise ArgumentError, message
      end

    if Map.has_key?(Session.pages(session), name) do
      raise ArgumentError, "page name #{inspect(name)} is already in use"
    end

    opener_id = Session.page_state(session).page_id

    predicate = fn %{params: %{page: %{guid: page_id}}} ->
      type == :page or
        Connection.initializer!(Session.context(session).connection, page_id)[:opener] == %{guid: opener_id}
    end

    {:ok, waiter} =
      EventWaiter.arm(Session.context(session).context_id, :page,
        predicate: predicate,
        connection: Session.context(session).connection,
        timeout: Keyword.fetch!(options, :timeout)
      )

    {:ok, session,
     %{
       type: :page,
       waiter: waiter,
       name: name,
       options: options
     }}
  end

  def arm_event(%Session{} = session, :dialog, options) do
    decision = Keyword.fetch!(options, :decision)
    deadline = Keyword.fetch!(options, :deadline)

    arm_waiter(session, :dialog, Session.page_state(session).page_id, :__create__, options,
      subscription: :dialog,
      predicate: &match?(%{params: %{type: "Dialog"}}, &1),
      transform: &handle_dialog(&1, decision, deadline, Session.context(session).connection)
    )
  end

  def arm_event(%Session{} = session, :file_chooser, options) do
    arm_waiter(session, :file_chooser, Session.page_state(session).page_id, :file_chooser, options)
  end

  def arm_event(%Session{} = session, type, options) when type in [:request, :response] do
    matcher = Keyword.fetch!(options, :matcher)
    normalize = &normalize_http_event(session, &1, type)
    predicate = &matches_network?(normalize.(&1), matcher, Session.context(session).base_url)

    arm_waiter(session, type, Session.context(session).context_id, type, options,
      predicate: predicate,
      transform: &{:ok, normalize.(&1)}
    )
  end

  def arm_event(%Session{} = session, type, options) do
    {:ok, session, %{type: type, options: options}}
  end

  @impl true
  def await_event(%Session{} = session, %{type: :download} = resource, _timeout) do
    with {:ok, download} <- BrowserPage.await_download(resource.waiter) do
      {:ok, session, normalize_download(download, resource.options, Session.context(session).timeout)}
    end
  end

  def await_event(%Session{} = session, %{type: :page} = resource, _timeout) do
    case EventWaiter.await(resource.waiter) do
      {:ok, %{params: %{page: %{guid: page_id}}}} ->
        deadline = Deadline.new(Session.context(session).timeout)

        initializer =
          Connection.initializer!(Session.context(session).connection, page_id)

        subscribe_to_console!(page_id, Session.context(session).connection, Deadline.remaining(deadline, 1))
        frame_id = initializer.main_frame.guid

        state = %State{
          context_id: Session.context(session).context_id,
          page_id: page_id,
          frame_id: frame_id
        }

        {:ok, snapshot} = Frame.snapshot(frame_id, connection: Session.context(session).connection)

        if http_document?(snapshot.url) do
          case Frame.wait_for_load_state(frame_id,
                 connection: Session.context(session).connection,
                 state: "load",
                 timeout: Deadline.remaining(deadline, 1)
               ) do
            {:ok, _result} -> :ok
            {:error, error} -> raise "Captured Playwright page did not load: #{inspect(error)}"
          end
        end

        {:ok, snapshot} = Frame.snapshot(frame_id, connection: Session.context(session).connection)
        state = %{state | document_identity: snapshot.document_ref}
        :ok = ready_navigated_document(state, snapshot.url, Deadline.remaining(deadline, 1))

        page = %Page.State{
          name: resource.name,
          driver: :playwright,
          state: state
        }

        session = Session.put_page(session, page)

        {:ok, session, Session.page_handle(session, resource.name)}

      {:ok, event} ->
        {:error, {:unexpected_page_event, event}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def await_event(%Session{} = session, %{type: type} = resource, _timeout)
      when type in [:dialog, :navigation, :request, :response] do
    with {:ok, result} <- EventWaiter.await(resource.waiter),
         {:ok, event} <- result do
      {:ok, session, event}
    end
  end

  def await_event(%Session{} = session, %{type: :file_chooser} = resource, _timeout) do
    with {:ok, %{guid: page_id, params: %{element: %{guid: element_id}, is_multiple: multiple?}}} <-
           EventWaiter.await(resource.waiter) do
      {:ok, session, %FileChooser{element_id: element_id, page_id: page_id, multiple?: multiple?}}
    end
  end

  def await_event(%Session{} = _session, _resource, _timeout), do: {:error, :timeout}

  @impl true
  def disarm_event(%{waiter: waiter}), do: EventWaiter.cancel(waiter)
  def disarm_event(_resource), do: :ok

  defp arm_waiter(session, type, guid, event, options, callbacks \\ []) do
    timeout = Keyword.fetch!(options, :timeout)
    deadline = Keyword.get_lazy(options, :deadline, fn -> Deadline.new(timeout) end)
    waiter_options = [connection: Session.context(session).connection, timeout: Deadline.remaining(deadline)]

    with {:ok, waiter} <- EventWaiter.arm(guid, event, Keyword.merge(waiter_options, callbacks)) do
      {:ok, session, %{type: type, waiter: waiter, options: options}}
    end
  end

  defp normalize_download(download, options, timeout) do
    filename = download.suggested_filename
    path = Path.join(System.tmp_dir!(), "fluffy-download-#{System.unique_integer([:positive])}")

    try do
      case BrowserDownload.save_as(download, path, timeout: timeout) do
        :ok -> :ok
        {:error, error} -> raise "Could not save Playwright download: #{inspect(error)}"
      end

      {:ok, stat} = File.stat(path)
      max_bytes = Keyword.fetch!(options, :max_bytes)

      if stat.size > max_bytes do
        raise ExUnit.AssertionError,
          message: "Downloaded #{stat.size} bytes, exceeding the configured :max_bytes limit of #{max_bytes}"
      end

      %Download{
        filename: filename,
        content_type: MIME.from_path(filename),
        bytes: File.read!(path),
        url: download.url
      }
    after
      _result = File.rm(path)
    end
  end

  defp navigation_status(session, _from_status, %{new_document: %{request: request}}) do
    with {:ok, response} <-
           Response.for_request(request,
             connection: Session.context(session).connection,
             timeout: Session.context(session).timeout
           ) do
      {:ok, response_status(response)}
    end
  end

  defp navigation_status(_session, _from_status, %{new_document: _document}), do: {:ok, nil}
  defp navigation_status(_session, from_status, _same_document), do: {:ok, from_status}

  defp release_page(session, page, :page_closed) do
    context = Session.context(session)

    case BrowserPage.close(page.state.page_id, connection: context.connection, timeout: context.timeout) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise "Could not close Playwright page #{inspect(page.id)}: #{inspect(error)}"
    end
  end

  defp handle_dialog(%{params: params}, decision, deadline, connection) do
    dialog = normalize_dialog(params.initializer)
    decision = if is_function(decision, 1), do: decision.(dialog), else: decision
    {action, prompt_text} = normalize_dialog_decision!(decision)
    timeout = Deadline.remaining(deadline, 1)

    result =
      case action do
        :accept ->
          accept_options =
            then([connection: connection, timeout: timeout], fn options ->
              if prompt_text, do: Keyword.put(options, :prompt_text, prompt_text), else: options
            end)

          BrowserDialog.accept(params.guid, accept_options)

        :dismiss ->
          BrowserDialog.dismiss(params.guid, connection: connection, timeout: timeout)
      end

    case result do
      {:ok, _result} -> {:ok, %{dialog | action: action, prompt_text: prompt_text}}
      {:error, error} -> {:error, {:dialog_handling_failed, error}}
    end
  end

  defp normalize_dialog(initializer) do
    %DialogResult{
      type: normalize_dialog_type(initializer.type),
      message: initializer.message,
      default_value: initializer.default_value || ""
    }
  end

  defp normalize_dialog_type(type) do
    case type do
      "alert" -> :alert
      "beforeunload" -> :beforeunload
      "confirm" -> :confirm
      "prompt" -> :prompt
      other -> other
    end
  end

  defp normalize_dialog_decision!(:accept), do: {:accept, nil}
  defp normalize_dialog_decision!(:dismiss), do: {:dismiss, nil}

  defp normalize_dialog_decision!({:accept, prompt_text}) when is_binary(prompt_text), do: {:accept, prompt_text}

  defp normalize_dialog_decision!(decision) do
    raise ArgumentError,
          "dialog decision callback returned invalid decision: #{inspect(decision)}"
  end

  defp normalize_http_event(session, %{params: params}, :request) do
    request = Connection.initializer!(Session.context(session).connection, params.request.guid)

    %HTTPEvent{
      kind: :request,
      method: request.method,
      url: request.url,
      headers: normalize_headers(request.headers),
      resource_type: request.resource_type,
      post_data: decode_protocol_binary(request[:post_data]),
      page: page_name(session, params[:page])
    }
  end

  defp normalize_http_event(session, %{params: params}, :response) do
    response = Connection.initializer!(Session.context(session).connection, params.response.guid)
    request = Connection.initializer!(Session.context(session).connection, response.request.guid)

    %HTTPEvent{
      kind: :response,
      method: request.method,
      url: response.url,
      headers: normalize_headers(response.headers),
      resource_type: request.resource_type,
      post_data: decode_protocol_binary(request[:post_data]),
      status: response.status,
      status_text: response.status_text,
      page: page_name(session, params[:page])
    }
  end

  defp normalize_headers(headers) do
    Map.new(headers, fn %{name: name, value: value} -> {String.downcase(name), value} end)
  end

  defp decode_protocol_binary(nil), do: nil

  defp decode_protocol_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> decoded
      :error -> value
    end
  end

  defp page_name(_session, nil), do: nil

  defp page_name(session, %{guid: page_id}) do
    Enum.find_value(Session.pages(session), fn {name, page} ->
      if page.state.page_id == page_id, do: name
    end)
  end

  defp matches_network?(event, matcher, _base_url) when is_function(matcher, 1), do: matcher.(event)

  defp matches_network?(event, %Regex{} = matcher, _base_url), do: Regex.match?(matcher, event.url)

  defp matches_network?(event, matcher, base_url) when is_binary(matcher) do
    expected = base_url |> URI.merge(matcher) |> URI.to_string()
    event.url == expected
  end

  defp adopt_navigated_document(session, state, url, timeout, live_navigation_cursor \\ nil) do
    {state, url} =
      if url do
        {state, url}
      else
        {:ok, snapshot} = Frame.snapshot(state.frame_id, connection: Session.context(session).connection)
        {%{state | document_identity: snapshot.document_ref}, snapshot.url}
      end

    :ok = ready_navigated_document(state, url, timeout, live_navigation_cursor)

    Session.commit_page(
      session,
      :playwright,
      state,
      url,
      live_redirect: not is_nil(live_navigation_cursor)
    )
  end

  defp ready_navigated_document(state, destination, timeout, live_navigation_cursor \\ nil) do
    deadline = Deadline.new(timeout)
    wait_for_live_view(state, destination, Deadline.remaining(deadline, 1), live_navigation_cursor)

    install_live_navigation_listener(state, destination, Deadline.remaining(deadline, 1))
  end

  defp response_status(%{status: status}), do: status
  defp response_status(_no_response), do: nil

  defp http_document?(url) do
    URI.parse(url).scheme in ["http", "https"]
  end

  defp new_page_state(context_id, page_id, frame_id) do
    %State{
      context_id: context_id,
      frame_id: frame_id,
      page_id: page_id
    }
  end

  defp wait_for_live_view(state, destination, timeout, live_navigation_cursor) do
    deadline = Deadline.new(timeout)

    wait_for_live_navigation_completion(
      state,
      destination,
      live_navigation_cursor,
      Deadline.remaining(deadline, 1)
    )

    result =
      Frame.wait_for_function(state.frame_id,
        expression: """
        () => document.readyState !== 'loading' &&
            Array.from(document.querySelectorAll('[data-phx-main], [data-phx-session]'))
          .every(element => element.classList.contains('phx-connected'))
        """,
        is_function: true,
        timeout: Deadline.remaining(deadline, 1)
      )

    case result do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise "LiveView browser connection failed for #{navigation_target(state, destination)}: expected every LiveView root to be .phx-connected, got #{inspect(error)}"
    end
  end

  defp install_live_navigation_listener(state, destination, timeout) do
    case Frame.evaluate(state.frame_id,
           expression: """
           () => {
             const eventKey = '__fluffyLiveNavigationEvents'

             if (!Array.isArray(window[eventKey])) {
               window[eventKey] = []
               window.addEventListener('phx:page-loading-start', event => {
                 const {kind, to} = event.detail ?? {}

                 if (kind === 'patch' || kind === 'redirect') {
                   window[eventKey].push({kind, to, complete: false})
                 }
               })
               window.addEventListener('phx:page-loading-stop', event => {
                 const {kind, to} = event.detail ?? {}
                 const pending = [...window[eventKey]].reverse().find(candidate =>
                   !candidate.complete && candidate.kind === kind && candidate.to === to
                 )

                 if (pending) pending.complete = true
               })
             }

             return true
           }
           """,
           is_function: true,
           timeout: timeout
         ) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise "Could not install the LiveView navigation observer for #{navigation_target(state, destination)}: #{inspect(error)}"
    end
  end

  defp wait_for_live_navigation_completion(_state, _destination, nil, _timeout), do: :ok

  defp wait_for_live_navigation_completion(state, destination, cursor, timeout) do
    case Frame.wait_for_function(state.frame_id,
           expression: """
           cursor => window.__fluffyLiveNavigationEvents
             ?.slice(cursor)
             .some(event => event.kind === 'redirect' && event.complete)
           """,
           is_function: true,
           arg: cursor,
           timeout: timeout
         ) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise "LiveView browser navigation failed for #{navigation_target(state, destination)}: expected redirect completion before [data-phx-main].phx-connected, got #{inspect(error)}"
    end
  end

  defp navigation_target(state, destination) do
    "destination #{inspect(destination)} (page #{inspect(state.page_id)}, frame #{inspect(state.frame_id)})"
  end

  defp timeout do
    :fluffy
    |> Application.fetch_env!(:playwright)
    |> Keyword.fetch!(:timeout)
  end

  defp subscribe_to_console!(page_id, connection, subscription_timeout \\ timeout()) do
    config = Application.fetch_env!(:fluffy, :playwright)

    if Keyword.get(config, :js_logger, Fluffy.Playwright.ConsoleLogger) != false do
      case BrowserPage.update_subscription(page_id,
             event: :console,
             enabled: true,
             connection: connection,
             timeout: subscription_timeout
           ) do
        {:ok, _result} -> :ok
        {:error, error} -> raise "Could not enable Playwright console logging: #{inspect(error)}"
      end
    end
  end

  defp normalize_browser_context_options(options) do
    Enum.map(options, fn
      {:storage_state, path} when is_binary(path) ->
        {:storage_state, path |> File.read!() |> Jason.decode!()}

      {:bypass_csp, value} ->
        {:bypassCSP, value}

      {key, :no_preference} when key in [:color_scheme, :contrast, :reduced_motion] ->
        {protocol_option_key(key), "no-preference"}

      option ->
        option
    end)
  end

  defp protocol_option_key(:color_scheme), do: :colorScheme
  defp protocol_option_key(:reduced_motion), do: :reducedMotion
  defp protocol_option_key(key), do: key

  defp deduplicate_headers(headers) do
    Enum.reduce(headers, [], fn {name, value}, result ->
      put_header(result, {String.downcase(to_string(name)), value})
    end)
  end

  defp put_header(headers, nil), do: headers

  defp put_header(headers, {name, value}) do
    headers
    |> Enum.reject(fn {header_name, _value} ->
      String.downcase(to_string(header_name)) == name
    end)
    |> Kernel.++([{name, value}])
  end
end
