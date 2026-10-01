defmodule Fluffy.Backend.Playwright do
  @moduledoc false

  @behaviour Fluffy.Backend.Contract

  alias Fluffy.Backend.Playwright.Context
  alias Fluffy.Backend.Playwright.Events
  alias Fluffy.BrowserRuntime
  alias Fluffy.Deadline
  alias Fluffy.Driver.Playwright.State
  alias Fluffy.FailureArtifact
  alias Fluffy.Internal.Navigation.BrowserCommitted
  alias Fluffy.Internal.Navigation.BrowserPatch
  alias Fluffy.Page
  alias Fluffy.PageLifecycle
  alias Fluffy.Playwright.Response
  alias Fluffy.Session
  alias PlaywrightEx.Browser
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Connection
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

    context_state = %Context{
      connection: connection,
      context_id: context.guid,
      tracing_id: context.tracing.guid,
      base_url: base_url,
      resource_scope: resource_scope,
      timeout: Keyword.get(options, :timeout, timeout())
    }

    page = page_record(context_state, browser_page.guid, :main)

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
  def prepare_page(context, page) do
    id = page.state.page_id
    opener = Connection.initializer!(context.connection, id)[:opener]
    opener_id = if opener, do: opener.guid
    {:ok, {%{page | url: nil, document_id: nil}, id, opener_id}}
  rescue
    ArgumentError -> {:error, "page #{inspect(page.name || page.id)} is closed"}
  end

  @impl true
  def subscribe_page(context, page, runtime) do
    id = page.state.page_id
    config = Application.fetch_env!(:fluffy, :playwright)
    event = if Keyword.get(config, :js_logger, Fluffy.Playwright.ConsoleLogger) == false, do: :close, else: :console

    case Connection.subscribe_event(context.connection, runtime, id, event) do
      :ok -> :ok
      {:error, _reason} -> {:error, "page #{inspect(page.name || page.id)} is closed"}
    end
  end

  @doc false
  def page_record(context, guid, name \\ nil) do
    initializer = Connection.initializer!(context.connection, guid)
    %Page.State{name: name, driver: :playwright, state: %State{page_id: guid, frame_id: initializer.main_frame.guid}}
  end

  @impl true
  def runtime_event(context, {:playwright_msg, %{method: :page, params: %{page: %{guid: guid}}}}) do
    # Read cached metadata only; page readiness remains in the action caller.
    page = page_record(context, guid)

    case prepare_page(context, page) do
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

    page = page_record(context, browser_page.guid, name)
    state = page.state
    {:ok, snapshot} = Frame.snapshot(state.frame_id, connection: context.connection)
    state = %{state | document_identity: snapshot.document_ref}
    page = %{page | state: state}
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
  defdelegate event_source(session, type, scope), to: Events

  @impl true
  defdelegate subscribe_event(session, type, source, pid), to: Events

  defp release_page(session, page, :page_closed) do
    context = Session.context(session)

    case BrowserPage.close(page.state.page_id, connection: context.connection, timeout: context.timeout) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise "Could not close Playwright page #{inspect(page.id)}: #{inspect(error)}"
    end
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

  defp ready_navigated_document(state, destination, timeout, live_navigation_cursor) do
    deadline = Deadline.new(timeout)
    wait_for_live_view(state, destination, Deadline.remaining(deadline, 1), live_navigation_cursor)

    install_live_navigation_listener(state, destination, Deadline.remaining(deadline, 1))
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
