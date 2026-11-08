defmodule Fluffy.Backend.Playwright do
  @moduledoc false

  @behaviour Fluffy.Backend.Contract

  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.Backend.Playwright.Context
  alias Fluffy.Backend.Playwright.Document
  alias Fluffy.Backend.Playwright.Events
  alias Fluffy.BrowserRuntime
  alias Fluffy.Deadline
  alias Fluffy.Driver.Playwright.State
  alias Fluffy.FailureArtifact
  alias Fluffy.Internal.Navigation.BrowserCommitted
  alias Fluffy.Internal.Navigation.BrowserPatch
  alias Fluffy.Page
  alias Fluffy.PageLifecycle
  alias Fluffy.Session
  alias Fluffy.SessionRuntime
  alias PlaywrightEx.Browser
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.ConsoleMessage
  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.TargetClosedError
  alias PlaywrightEx.Tracing
  alias PlaywrightEx.WebError

  require Logger

  @impl true
  def start_session(options, attachment) do
    {resource_scope, runtime, sandbox_header} = attachment
    base_url = Keyword.fetch!(options, :base_url)
    timeout = Keyword.get(options, :timeout, timeout())
    browser_context_options = Keyword.get(options, :browser_context, [])

    headers =
      browser_context_options
      |> Keyword.get(:extra_http_headers, %{})
      |> Enum.concat(Keyword.get(options, :headers, []))
      |> Enum.concat(List.wrap(sandbox_header))
      |> Map.new(fn {name, value} -> {String.downcase(to_string(name)), value} end)

    context_options =
      browser_context_options
      |> Keyword.put_new(:locale, "en")
      |> Keyword.put(:base_url, base_url)
      |> Keyword.put(:extra_http_headers, headers)

    # The runtime creates and closes the context: PlaywrightEx keeps a closed
    # context's data until those processes exit. Its cleanup is registered
    # before any further setup can fail.
    browser_context = SessionRuntime.run(runtime, fn -> new_context!(context_options) end)

    # The runtime waits at most `timeout` for the close, which has no timeout of
    # its own; a slower close continues unlinked rather than leaving the context
    # open in the shared browser.
    :ok =
      SessionRuntime.register(runtime, {:browser_context, browser_context.guid}, fn ->
        task = Task.Supervisor.async_nolink(Fluffy.TaskSupervisor, fn -> BrowserContext.close(browser_context) end)
        Task.yield(task, timeout)
      end)

    SessionRuntime.run(runtime, fn ->
      :ok = BrowserContext.set_default_timeout(browser_context, timeout)
      _disposable = BrowserContext.add_init_script!(browser_context, Document.init_script())
    end)

    listen(browser_context, runtime)
    browser_page = BrowserContext.new_page!(browser_context)

    context = %Context{
      browser_context: browser_context,
      base_url: base_url,
      resource_scope: resource_scope,
      timeout: timeout
    }

    Session.new(__MODULE__, context, page_record(browser_page), runtime)
  end

  # A lost driver closes its contexts before its browser, so a session can start
  # before the browser runtime learns of the loss. That browser refuses contexts.
  defp new_context!(options) do
    browser = BrowserRuntime.browser()

    case Browser.new_context(browser, options) do
      {:ok, browser_context} -> browser_context
      {:error, %TargetClosedError{}} -> Browser.new_context!(BrowserRuntime.replace(browser), options)
      {:error, error} -> raise error
    end
  end

  # Listeners only forward. The runtime does the work, and receives each
  # message before the reply of the call that caused it.
  defp listen(browser_context, runtime) do
    forward = fn kind -> fn native -> send(runtime, {:fluffy_playwright, kind, native}) end end

    BrowserContext.on(browser_context, :page, forward.(:page))
    BrowserContext.on(browser_context, :close, forward.(:context_close))

    if Keyword.get(Application.fetch_env!(:fluffy, :playwright), :log_browser_console, true) do
      BrowserContext.on(browser_context, :console, forward.(:console))
      BrowserContext.on(browser_context, :web_error, forward.(:web_error))
    end
  end

  @impl true
  def page_snapshot(context, page) do
    document_id = {document_identity(context, page.state), page.document_id}
    %{page | url: BrowserPage.url(page.state.page), document_id: document_id}
  end

  # Actions adopt the document they find. One that page code navigated to
  # since is read from the page; a closed or unresponsive page keeps the
  # adopted identity.
  defp document_identity(context, state) do
    if Document.navigated?(state),
      do: Document.probe!(state.frame, nil, context.timeout).document,
      else: state.document_identity
  rescue
    _error -> state.document_identity
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
  def prepare_page(_context, page) do
    browser_page = page.state.page

    case BrowserPage.opener(browser_page) do
      {:ok, opener} -> {:ok, {%{page | url: nil, document_id: nil}, browser_page.guid, opener && opener.guid}}
      {:error, _error} -> {:error, "page #{inspect(page.id)} is closed"}
    end
  end

  @impl true
  def subscribe_page(_context, page, runtime) do
    browser_page = page.state.page
    listener = fn closed -> send(runtime, {:fluffy_playwright, :page_close, closed}) end
    navigated = Document.navigation_listener(page.state)
    # Listening first misses no close; a page closed before keeps no listener.
    BrowserPage.on(browser_page, :close, listener)
    BrowserPage.on(browser_page, :frame_navigated, navigated)

    if BrowserPage.is_closed(browser_page) do
      BrowserPage.off(browser_page, :close, listener)
      BrowserPage.off(browser_page, :frame_navigated, navigated)
      {:error, "page #{inspect(page.id)} is closed"}
    else
      :ok
    end
  end

  @doc false
  def page_record(browser_page) do
    # A page's document is unknown until Fluffy reads it.
    navigated = :atomics.new(1, [])
    :atomics.put(navigated, 1, 1)
    state = %State{page: browser_page, frame: BrowserPage.main_frame(browser_page), navigated: navigated}
    %Page.State{driver: :playwright, state: state}
  end

  @impl true
  def runtime_event(context, {:fluffy_playwright, :page, browser_page}) do
    # Read cached metadata only; page readiness remains in the action caller.
    case prepare_page(context, page_record(browser_page)) do
      {:ok, registration} -> {:page_opened, registration}
      {:error, _} -> :ignore
    end
  end

  def runtime_event(_context, {:fluffy_playwright, :context_close, _browser_context}), do: :closed
  def runtime_event(_context, {:fluffy_playwright, :page_close, browser_page}), do: {:page_closed, browser_page.guid}

  def runtime_event(_context, {:fluffy_playwright, :console, message}) do
    log(console_level(ConsoleMessage.type(message)), ConsoleMessage.text(message), ConsoleMessage.location(message))
  end

  def runtime_event(_context, {:fluffy_playwright, :web_error, error}) do
    log(:error, web_error_text(WebError.error(error)), nil)
  end

  def runtime_event(_context, _message), do: :ignore

  defp log(level, text, location) do
    Logger.log(level, append_location(text, location), fluffy: :playwright)
    :ignore
  end

  # PlaywrightEx can return a value page code threw that is not an Error as it is, though
  # `WebError.error/1` is specced as an exception.
  @dialyzer {:nowarn_function, web_error_text: 1}
  defp web_error_text(error) when is_exception(error), do: Exception.message(error)
  defp web_error_text(error) when is_binary(error), do: error
  defp web_error_text(error), do: inspect(error)

  defp console_level("error"), do: :error
  defp console_level("warning"), do: :warning
  defp console_level("debug"), do: :debug
  defp console_level(_type), do: :info

  defp append_location(text, %{url: url, line: line, column: column}) when url != "" and is_integer(line) and line > 0,
    do: "#{text} (#{url}:#{line}:#{column})"

  defp append_location(text, %{url: url}) when is_binary(url) and url != "", do: "#{text} (#{url})"
  defp append_location(text, _location), do: text

  @impl true
  def run_step(session, name, location, fun) do
    context = Session.context(session)

    if context.trace do
      tracing = BrowserContext.tracing(context.browser_context)
      Tracing.group!(tracing, name, location: Map.new(location))

      try do
        fun.()
      after
        Tracing.group_end(tracing)
      end
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
    timeout = Session.context(session).timeout
    _response = navigate!(:goto, [state.page, path, [wait_until: :load, timeout: timeout]])
    adopt_navigated_document(session, state, timeout)
  end

  @impl true
  def reload(%Session{} = session, options \\ []) do
    state = Session.page_state(session)
    native = navigation_options(session, options)
    _response = navigate!(:reload, [state.page, native])
    # Bookkeeping uses the session timeout, as after other actions.
    adopt_navigated_document(session, state, Session.timeout(session))
  end

  @impl true
  def navigate(%Session{} = session, %BrowserCommitted{state: state, url: url, live_navigation_cursor: cursor}) do
    timeout = Session.context(session).timeout

    if cursor do
      :ok = ready_navigated_document(state, url, timeout, cursor)
      Session.commit_page(session, :playwright, state, url, live_redirect: true)
    else
      adopt_document(session, state, url, timeout)
    end
  end

  def navigate(%Session{} = session, %BrowserPatch{state: state, url: url}) do
    Session.commit_page(session, :playwright, state, url, same_document: true)
  end

  @impl true
  def new_page(session) do
    context = Session.context(session)
    browser_page = BrowserContext.new_page!(context.browser_context)
    Session.register_page(session, page_record(browser_page))
  end

  @impl true
  def history(session, direction, options) do
    state = Session.page_state(session)
    session_timeout = Session.timeout(session)
    previous_url = Session.current_page(session).url
    native = navigation_options(session, options)
    response = navigate!(direction, [state.page, native])
    # Bookkeeping uses the session timeout, as after other actions.
    probe = Document.adopted_probe!(state, nil, session_timeout)

    if is_nil(response) and probe.url == previous_url and probe.document == state.document_identity,
      do: session,
      else: adopt_probed_document(session, state, probe, session_timeout)
  end

  @impl true
  def close_page(%Session{} = session, page_id) do
    PageLifecycle.close_page(session, page_id, &release_page/3)
  end

  @impl true
  defdelegate event_source(session, type, scope), to: Events

  @impl true
  defdelegate subscribe_event(session, type, source, pid), to: Events

  # Like closing the context, closing a page has no timeout of its own.
  defp release_page(session, page, :page_closed) do
    timeout = Session.timeout(session)
    Bounded.within!(timeout, :close_page, fn -> with :ok <- BrowserPage.close(page.state.page), do: {:ok, :ok} end)
    :ok
  end

  # Like visit/2, reload and history wait for the load event by default.
  defp navigation_options(session, options),
    do: Keyword.merge([wait_until: :load], Keyword.put(options, :timeout, Session.timeout(session, options)))

  defp navigate!(operation, arguments) do
    case apply(BrowserPage, operation, arguments) do
      {:ok, response} -> response
      {:error, error} -> raise "Playwright #{operation} failed: " <> Exception.message(error)
    end
  end

  defp adopt_navigated_document(session, state, timeout) do
    adopt_probed_document(session, state, Document.adopted_probe!(state, nil, timeout), timeout)
  end

  defp adopt_probed_document(session, state, probe, timeout) do
    state = %{state | document_identity: probe.document}
    adopt_document(session, state, probe.url, timeout)
  end

  defp adopt_document(session, state, url, timeout) do
    :ok = ready_navigated_document(state, url, timeout, nil)
    Session.commit_page(session, :playwright, state, url)
  end

  defp ready_navigated_document(state, destination, timeout, cursor) do
    deadline = Deadline.new(timeout)
    if cursor, do: Document.wait_for_redirect!(state.frame, destination, cursor, Deadline.remaining(deadline, 1))
    Document.wait_for_live_view!(state.frame, destination, Deadline.remaining(deadline, 1))
  end

  defp timeout do
    :fluffy
    |> Application.fetch_env!(:playwright)
    |> Keyword.fetch!(:timeout)
  end
end
