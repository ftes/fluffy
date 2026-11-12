defmodule Fluffy.Backend.Playwright do
  @moduledoc false

  @behaviour Fluffy.Backend.Contract

  alias Fluffy.Backend.Playwright.Context
  alias Fluffy.Backend.Playwright.Document
  alias Fluffy.Backend.Playwright.Events
  alias Fluffy.Deadline
  alias Fluffy.Driver.Playwright.State
  alias Fluffy.Internal.Navigation.BrowserCommitted
  alias Fluffy.Internal.Navigation.BrowserPatch
  alias Fluffy.Internal.OperationFailure
  alias Fluffy.Options
  alias Fluffy.Page
  alias Fluffy.PageLifecycle
  alias Fluffy.Session
  alias Fluffy.SessionRuntime
  alias Fluffy.TestScope
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.ConsoleMessage
  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.TargetClosedError
  alias PlaywrightEx.WebError

  require Logger

  @impl true
  def start_session(options, attachment) do
    {resource_scope, runtime, sandbox_header} = attachment
    # An unmanaged session (no scope) is no test's: PlaywrightEx.Test records nothing of it.
    test_context = if resource_scope, do: TestScope.metadata(resource_scope), else: %{}
    base_url = Keyword.fetch!(options, :base_url)
    config = Options.playwright_config()
    timeout = Keyword.get_lazy(options, :timeout, fn -> Keyword.fetch!(config, :timeout) end)
    browser_context_options = Keyword.get(options, :browser_context, [])

    headers =
      browser_context_options
      |> Keyword.get(:extra_http_headers, %{})
      |> Enum.concat(Keyword.get(options, :headers, []))
      |> Enum.concat(List.wrap(sandbox_header))
      |> Map.new(fn {name, value} -> {String.downcase(to_string(name)), value} end)

    context_options =
      browser_context_options
      # Playwright Test's default.
      |> Keyword.put_new(:locale, "en-US")
      |> Keyword.put(:base_url, base_url)
      |> Keyword.put(:extra_http_headers, headers)

    # The runtime creates and closes the context: PlaywrightEx keeps a closed
    # context's data until those processes exit. Its cleanup is registered in
    # the same runtime call, before any further setup can fail.
    browser_context =
      SessionRuntime.run_registered(runtime, fn ->
        browser_context = new_context!(context_options, test_context)

        # As in Playwright, closing the context has no timeout.
        close = fn -> BrowserContext.close(browser_context) end

        {browser_context, {:browser_context, browser_context.guid}, close}
      end)

    SessionRuntime.run(runtime, fn ->
      :ok = BrowserContext.set_default_timeout(browser_context, timeout)
      _disposable = BrowserContext.add_init_script!(browser_context, Document.init_script())
    end)

    listen(browser_context, runtime, Keyword.fetch!(config, :log_browser_console))
    browser_page = BrowserContext.new_page!(browser_context)

    context = %Context{
      browser_context: browser_context,
      base_url: base_url,
      extra_http_headers: headers,
      resource_scope: resource_scope,
      timeout: timeout
    }

    Session.new(__MODULE__, context, page_record(browser_page), runtime)
  end

  # PlaywrightEx.Test records the context for the test's `test_pid` (traces, screenshots,
  # videos). A browser lost to a dead driver still refuses contexts until its disconnect
  # arrives; as in Playwright Test, that session fails.
  defp new_context!(options, test_context) do
    test_context
    |> Map.put(:browser, browser(test_context).browser)
    |> PlaywrightEx.Test.new_context(context_options: options)
    |> Map.fetch!(:context)
  end

  @doc false
  # The test's browser from PlaywrightEx.Test's pool, set up by `config :playwright_ex,
  # :test`: shared, or with `isolate: true` the module's own driver and browser, checked
  # out at its first session. An unmanaged session has no module: it shares.
  def browser(test_context) do
    if Keyword.fetch!(Options.playwright_config(), :isolate) and is_map_key(test_context, :module),
      do: PlaywrightEx.Test.browser(test_context, isolate: true),
      else: PlaywrightEx.Test.browser([])
  end

  # Listeners only forward. The runtime does the work, and receives each
  # message before the reply of the call that caused it.
  defp listen(browser_context, runtime, log_browser_console?) do
    forward = fn kind -> fn native -> send(runtime, {:fluffy_playwright, kind, native}) end end

    BrowserContext.on(browser_context, :page, forward.(:page))
    BrowserContext.on(browser_context, :close, forward.(:context_close))

    if log_browser_console? do
      BrowserContext.on(browser_context, :console, forward.(:console))
      BrowserContext.on(browser_context, :web_error, forward.(:web_error))
    end
  end

  @impl true
  def page_snapshot(_context, page) do
    document_id = {document_identity(page.state), page.document_id}
    %{page | url: BrowserPage.url(page.state.page), document_id: document_id}
  end

  # Reading metadata such as a page's URL must not wait out a page blocked by
  # a dialog or a long script.
  @snapshot_probe_timeout 300

  # Actions adopt the document they find. One that page code navigated to
  # since is read from the page; a closed or unresponsive page keeps the
  # adopted identity. The probe raises a `RuntimeError` when the page does not
  # respond and PlaywrightEx's error when the page is closed or the read fails.
  defp document_identity(state) do
    if Document.navigated?(state),
      do: Document.probe!(state.frame, nil, @snapshot_probe_timeout).document,
      else: state.document_identity
  rescue
    _error in [RuntimeError, PlaywrightEx.PlaywrightError, PlaywrightEx.TimeoutError, TargetClosedError] ->
      state.document_identity
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
    log(:error, Exception.message(WebError.error(error)), nil)
  end

  def runtime_event(_context, _message), do: :ignore

  defp log(level, text, location) do
    Logger.log(level, append_location(text, location), fluffy: :playwright)
    :ignore
  end

  defp console_level("error"), do: :error
  defp console_level("warning"), do: :warning
  defp console_level("debug"), do: :debug
  defp console_level(_type), do: :info

  defp append_location(text, %{url: url, line: line, column: column}) when url != "" and is_integer(line) and line > 0,
    do: "#{text} (#{url}:#{line}:#{column})"

  defp append_location(text, %{url: url}) when is_binary(url) and url != "", do: "#{text} (#{url})"
  defp append_location(text, _location), do: text

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

    navigation!(:visit, fn ->
      _response = navigate!(:goto, [state.page, path, [timeout: timeout]])
      adopt_navigated_document(session, state)
    end)
  end

  @impl true
  def reload(%Session{} = session, options \\ []) do
    state = Session.page_state(session)
    native = navigation_options(session, :reload, options)

    navigation!(:reload, fn ->
      _response = navigate!(:reload, [state.page, native])
      adopt_navigated_document(session, state)
    end)
  end

  @impl true
  def navigate(%Session{} = session, %BrowserCommitted{state: state, url: url, live_navigation_cursor: cursor}) do
    timeout = Document.bookkeeping_timeout(session)

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
    timeout = Document.bookkeeping_timeout(session)
    previous_url = Session.current_page(session).url
    native = navigation_options(session, direction, options)

    navigation!(direction, fn ->
      response = navigate!(direction, [state.page, native])
      probe = Document.adopted_probe!(state, nil, timeout)

      if is_nil(response) and probe.url == previous_url and probe.document == state.document_identity,
        do: session,
        else: adopt_probed_document(session, state, probe, timeout)
    end)
  end

  @impl true
  def close_page(%Session{} = session, page_id) do
    PageLifecycle.close_page(session, page_id, &release_page/3)
  end

  @impl true
  defdelegate event_source(session, type, scope), to: Events

  @impl true
  defdelegate subscribe_event(session, type, source, pid), to: Events

  # As in Playwright, closing a page has no timeout.
  defp release_page(_session, page, :page_closed) do
    with {:error, error} <- BrowserPage.close(page.state.page), do: raise(error)
  end

  # As in Playwright, `wait_until:` defaults to `:load`. Like an action, a
  # navigation can't check once, so it rejects Fluffy's `timeout: 0`.
  defp navigation_options(session, operation, options),
    do: Keyword.put(options, :timeout, Session.operation_timeout!(session, operation, options))

  # As for an action, PlaywrightEx's error, which keeps Playwright's call log,
  # becomes the cause of a `Fluffy.OperationError`.
  defp navigation!(operation, fun) do
    fun.()
  rescue
    error in [PlaywrightEx.PlaywrightError, PlaywrightEx.TimeoutError, TargetClosedError] ->
      reraise OperationFailure.playwright(operation, nil, error), __STACKTRACE__
  end

  defp navigate!(operation, arguments) do
    case apply(BrowserPage, operation, arguments) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end

  defp adopt_navigated_document(session, state) do
    timeout = Document.bookkeeping_timeout(session)
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
end
