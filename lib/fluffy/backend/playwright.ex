defmodule Fluffy.Backend.Playwright do
  @moduledoc false

  @behaviour Fluffy.Backend.Contract

  alias Fluffy.Backend.Playwright.Context
  alias Fluffy.Backend.Playwright.Events
  alias Fluffy.Deadline
  alias Fluffy.Driver.Playwright, as: PlaywrightDriver
  alias Fluffy.Driver.Playwright.Document
  alias Fluffy.Driver.Playwright.State
  alias Fluffy.Internal.NavigationFailure
  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.SessionRuntime
  alias Fluffy.Timeouts
  alias Playwright.BrowserContext
  alias Playwright.Page, as: BrowserPage
  alias Playwright.TargetClosedError

  @impl true
  def start_session(options) do
    # The session belongs to the test, also when a Task of it starts the session.
    %{test_pid: test_pid} = test_info = Fluffy.TestInfo.fetch!()
    base_url = Keyword.fetch!(options, :base_url)
    browser_context_options = Keyword.get(options, :browser_context, [])

    # As in Playwright, the session's `extra_http_headers` replace the test's as a whole; the
    # sandbox's metadata goes with them.
    headers =
      (options[:extra_http_headers] || test_info.use[:extra_http_headers] || %{})
      |> Enum.concat(List.wrap(Fluffy.Sandbox.metadata_header(test_pid)))
      |> Map.new(fn {name, value} -> {String.downcase(to_string(name)), value} end)

    # Before the runtime's `on_exit`, so the test waits for its LiveViews once its sessions are closed.
    Fluffy.Sandbox.await_exits_on_exit(test_pid)
    runtime = SessionRuntime.start!(test_pid)

    try do
      # Playwright.Test records the context for the test and gives it Playwright Test's
      # defaults, also from a process with the test in `$callers`; the runtime closes it with
      # the session. As in Playwright, closing has
      # no timeout. A browser lost to a dead driver still refuses contexts until its
      # disconnect arrives; as in Playwright Test, that session fails. The default browser is
      # the test's lease of the pool, taken here so a test without a Playwright session takes none.
      browser_context =
        options
        |> Keyword.get_lazy(:browser, &Playwright.Test.BrowserPool.browser/0)
        |> Playwright.Browser.new_context!(browser_context_options ++ [base_url: base_url, extra_http_headers: headers])

      :ok =
        SessionRuntime.register(runtime, {:browser_context, browser_context.guid}, fn ->
          BrowserContext.close(browser_context)
        end)

      # The test's action and navigation timeouts, as Playwright.Test sets them on its contexts.
      context = %Context{
        browser_context: browser_context,
        base_url: base_url,
        endpoint: options[:endpoint],
        extra_http_headers: headers,
        action_timeout: Timeouts.no_limit(test_info.use.action_timeout),
        navigation_timeout: Timeouts.no_limit(test_info.use.navigation_timeout)
      }

      SessionRuntime.run(runtime, fn ->
        _disposable = BrowserContext.add_init_script!(browser_context, Document.init_script())
      end)

      listen(browser_context, runtime)
      browser_page = BrowserContext.new_page!(browser_context)
      Session.new(__MODULE__, context, page_record(browser_page), runtime)
    rescue
      error ->
        SessionRuntime.close(runtime)
        reraise error, __STACKTRACE__
    end
  end

  # Listeners only forward. The runtime does the work, and receives each
  # message before the reply of the call that caused it.
  defp listen(browser_context, runtime) do
    forward = fn kind -> fn native -> send(runtime, {:fluffy_playwright, kind, native}) end end

    BrowserContext.on(browser_context, :page, forward.(:page))
    BrowserContext.on(browser_context, :close, forward.(:context_close))
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
  # adopted identity. The probe raises a `NavigationFailure` when the page does not
  # respond and Playwright's error when the page is closed or the read fails.
  defp document_identity(state) do
    if Document.navigated?(state),
      do: Document.probe!(state.frame, nil, @snapshot_probe_timeout).document,
      else: state.document_identity
  rescue
    _error in [NavigationFailure, Playwright.PlaywrightError, Playwright.TimeoutError, TargetClosedError] ->
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
    %Page.State{driver: :playwright, state: State.new(browser_page)}
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

  def runtime_event(_context, _message), do: :ignore

  @impl true
  def base_url(%Session{} = session), do: Session.context(session).base_url

  @impl true
  def endpoint(%Session{} = session), do: Session.context(session).endpoint

  # As in Playwright, these have no timeout.
  @impl true
  def add_cookies(%Session{} = session, cookies) do
    :ok = BrowserContext.add_cookies!(Session.context(session).browser_context, cookies)
    session
  end

  @impl true
  def cookies(%Session{} = session, urls), do: BrowserContext.cookies!(Session.context(session).browser_context, urls)

  @impl true
  def clear_cookies(%Session{} = session, options) do
    :ok = BrowserContext.clear_cookies!(Session.context(session).browser_context, options)
    session
  end

  @impl true
  def visit(%Session{} = session, path) do
    state = Session.page_state(session)
    timeout = Timeouts.navigation(session)

    _response = navigate!(:goto, [state.page, path, [timeout: timeout]])
    PlaywrightDriver.adopt_navigated_document(session, state)
  end

  @impl true
  def reload(%Session{} = session, options \\ []) do
    state = Session.page_state(session)
    native = navigation_options(session, :reload, options)

    _response = navigate!(:reload, [state.page, native])
    PlaywrightDriver.adopt_navigated_document(session, state)
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
    timeout = Document.bookkeeping_timeout(Timeouts.navigation(session))
    previous_url = Session.current_page(session).url
    native = navigation_options(session, direction, options)

    response = navigate!(direction, [state.page, native])
    probe = Document.adopted_probe!(state, nil, timeout)

    if is_nil(response) and probe.url == previous_url and probe.document == state.document_identity,
      do: session,
      else: PlaywrightDriver.adopt_probed_document(session, state, probe)
  end

  # As in Playwright, closing a page has no timeout.
  @impl true
  def close_page(%Session{} = session, page) do
    handle = Session.page_handle(session, page)
    with {:error, error} <- BrowserPage.close(Page.record(handle).state.page), do: raise(error)
    SessionRuntime.close_page(session.runtime, Page.id(handle))
    session
  end

  @impl true
  defdelegate event_source(session, type, scope), to: Events

  @impl true
  defdelegate subscribe_event(session, type, source, pid), to: Events

  # As in Playwright, `wait_until:` defaults to `:load`. Like an action, a
  # navigation can't check once, so it rejects Fluffy's `timeout: 0`.
  defp navigation_options(session, operation, options) do
    timeout = Timeouts.operation(session, operation, options)
    Keyword.put(options, :timeout, Deadline.playwright_operation!(operation, timeout))
  end

  defp navigate!(operation, arguments) do
    case apply(BrowserPage, operation, arguments) do
      {:ok, response} -> response
      {:error, error} -> raise error
    end
  end
end
