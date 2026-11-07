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
      |> Enum.reduce(%{}, fn {name, value}, headers ->
        name = String.downcase(to_string(name))
        headers |> Map.reject(fn {existing, _value} -> String.downcase(existing) == name end) |> Map.put(name, value)
      end)

    context_options =
      browser_context_options
      |> Keyword.put_new(:locale, "en")
      |> Keyword.put(:base_url, base_url)
      |> Keyword.put(:extra_http_headers, headers)

    # The runtime creates and closes the context: PlaywrightEx keeps a closed
    # context's data until those processes exit. Its cleanup is registered
    # before any further setup can fail.
    browser_context = SessionRuntime.run(runtime, fn -> new_context!(context_options) end)

    :ok =
      SessionRuntime.register(runtime, {:browser_context, browser_context.guid}, fn ->
        Bounded.within(timeout, fn -> BrowserContext.close(browser_context) end)
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
  def page_snapshot(_context, page) do
    %{page | url: BrowserPage.url(page.state.page), document_id: {page.state.document_identity, page.document_id}}
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
    # Listening first misses no close; a page closed before keeps no listener.
    BrowserPage.on(browser_page, :close, listener)

    if BrowserPage.is_closed(browser_page) do
      BrowserPage.off(browser_page, :close, listener)
      {:error, "page #{inspect(page.id)} is closed"}
    else
      :ok
    end
  end

  @doc false
  def page_record(browser_page) do
    %Page.State{driver: :playwright, state: %State{page: browser_page, frame: BrowserPage.main_frame(browser_page)}}
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
    {timeout, options} = Keyword.pop(options, :timeout, Session.context(session).timeout)
    timeout = max(timeout, 1)
    _response = navigate!(:reload, [state.page, Keyword.merge([wait_until: :load, timeout: timeout], options)])
    adopt_navigated_document(session, state, timeout)
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
    session_timeout = max(Session.context(session).timeout, 1)
    {timeout, options} = Keyword.pop(options, :timeout, session_timeout)
    previous_url = Session.current_page(session).url
    native = Keyword.merge([wait_until: :load, timeout: max(timeout, 1)], options)
    response = navigate!(direction, [state.page, native])
    # Bookkeeping uses the session timeout, as after other actions.
    probe = Document.probe!(state.frame, nil, session_timeout)

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
    timeout = max(Session.context(session).timeout, 1)
    Bounded.within!(timeout, :close_page, fn -> with :ok <- BrowserPage.close(page.state.page), do: {:ok, :ok} end)
    :ok
  end

  defp navigate!(operation, arguments) do
    case apply(BrowserPage, operation, arguments) do
      {:ok, response} -> response
      {:error, error} -> raise "Playwright #{operation} failed: " <> Exception.message(error)
    end
  end

  defp adopt_navigated_document(session, state, timeout) do
    adopt_probed_document(session, state, Document.probe!(state.frame, nil, timeout), timeout)
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
