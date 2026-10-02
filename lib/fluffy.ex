defmodule Fluffy do
  @moduledoc """
  Pipeable feature testing for Phoenix applications.

  Start a session with the Phoenix (`:phoenix`) or Playwright (`:playwright`)
  backend, then compose locators, actions, expectations, and event waits.
  Import `Fluffy.Expect` for expectations, or use `Fluffy.Assert` for
  ExUnit-style assertions. The
  Phoenix backend selects its Static (`Phoenix.ConnTest`) or LiveView
  (`Phoenix.LiveViewTest`) driver for each page; the Playwright backend uses the
  Playwright driver.

  Unless a function documents additional entries, action, assertion, reload,
  and event-wait option lists accept:

  #{NimbleOptions.docs(Fluffy.Options.action_schema())}
  """
  @moduledoc groups: [
               "Lifecycle and navigation",
               "Actions",
               "Events",
               "Diagnostics and native access"
             ]

  alias Fluffy.Backend
  alias Fluffy.Driver.Registry, as: DriverRegistry
  alias Fluffy.Event
  alias Fluffy.Event.Pending
  alias Fluffy.Expect
  alias Fluffy.SelectedFile
  alias Fluffy.Session

  @shared_press_keys ["Enter", "Space", "Tab"]

  @doc group: "Lifecycle and navigation"
  @doc """
  Starts an isolated `:phoenix` or `:playwright` session.

  Configure the application endpoint once with
  `config :fluffy, endpoint: MyAppWeb.Endpoint`. The session base URL uses the
  endpoint's active HTTP or HTTPS listener when available and otherwise falls
  back to `MyAppWeb.Endpoint.url()`. An explicit `:endpoint` or `:base_url`
  option overrides the application configuration for this session.

  ## Options

  #{NimbleOptions.docs(Fluffy.Options.session_schema())}
  """
  @type backend :: :phoenix | :playwright
  @type action_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema()))
  @type file_input_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.file_input_schema()))
  @type session_option ::
          unquote(NimbleOptions.option_typespec(Fluffy.Options.session_schema()))

  @spec start_session(backend(), [session_option()]) :: Session.t()
  def start_session(backend, options \\ []), do: Backend.start_session(backend, options)

  @doc group: "Lifecycle and navigation"
  @doc "Closes a session and its resources. Returns `:ok` or `{:error, reason}`."
  def close_session(%Session{} = session), do: Backend.close_session(session)

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Creates a blank page in the session's browser context and returns its handle.

  The session keeps its current page selection. Use `switch_page/2` to select
  the new page. Pages share the context's cookies and storage.

      main = current_page(session)
      other = new_page(session)

      session
      |> switch_page(other)
      |> visit("/dashboard")
      |> switch_page(main)
  """
  @spec new_page(Session.t()) :: Fluffy.Page.t()
  def new_page(%Session{} = session), do: Backend.new_page(session)

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Navigates backward in browser history. Does nothing if there is no entry."
  def go_back(%Session{} = session, options \\ []) do
    Backend.history(session, :go_back, Fluffy.Options.validate_action!(options))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Navigates forward in browser history. Does nothing if there is no entry."
  def go_forward(%Session{} = session, options \\ []) do
    Backend.history(session, :go_forward, Fluffy.Options.validate_action!(options))
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Hovers over a locator. Requires Playwright."
  def hover(%Session{} = session, locator, options \\ []) do
    require_playwright!(session, :hover)
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :hover, [locator, options])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Drags the source locator onto the target locator in the same frame. Requires Playwright."
  def drag_to(%Session{} = session, source, target, options \\ []) do
    require_playwright!(session, :drag_to)
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :drag_to, [source, target, options])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Types text character by character, emitting keyboard events. Accepts `:delay` in milliseconds. Requires Playwright."
  def press_sequentially(%Session{} = session, locator, text, options \\ []) do
    require_playwright!(session, :press_sequentially)
    options = validate_typing!(options)
    dispatch_driver(session, :press_sequentially, [locator, text, options])
  end

  defp validate_typing!(options) do
    {delay, options} = Keyword.pop(options, :delay, 0)
    if !(is_integer(delay) and delay >= 0), do: raise(ArgumentError, "delay must be a non-negative integer")
    Keyword.put(Fluffy.Options.validate_action!(options), :delay, delay)
  end

  defp require_playwright!(session, capability) do
    if Session.backend(session) != Fluffy.Backend.Playwright do
      raise Fluffy.CapabilityError,
        capability: capability,
        driver: Session.current_driver(session),
        detail: "This operation requires Playwright"
    end
  end

  @doc group: "Diagnostics and native access"
  @doc """
  Groups the operations in `fun` under a named diagnostic step.

  Playwright sessions with tracing enabled record a nested trace group at the
  call site's source location. Phoenix sessions and untraced Playwright
  sessions simply run the callback. The callback must return the updated
  session, which is also returned by `step/3`.
  """
  defmacro step(session, name, fun) do
    location = [file: Path.absname(__CALLER__.file), line: __CALLER__.line]

    quote do
      Fluffy.__step__(unquote(session), unquote(name), unquote(fun), unquote(location))
    end
  end

  @doc false
  def __step__(%Session{} = session, name, fun, location) when is_binary(name) and is_function(fun, 1) do
    result = Backend.run_step(session, name, location, fn -> fun.(session) end)

    case result do
      %Session{} = updated_session ->
        updated_session

      other ->
        raise ArgumentError,
              "Fluffy.step/3 callback must return a Fluffy.Session, got: #{inspect(other)}"
    end
  end

  @doc group: "Diagnostics and native access"
  @doc """
  Opens a temporary HTML snapshot of the active page in your default browser.

  Returns the unchanged session so it can be used in a pipeline. LiveView pages
  use `Phoenix.LiveViewTest.open_browser/1`. Static pages resolve local assets
  through the session endpoint; Playwright pages resolve assets against the page
  URL. Scripts are removed. This is an HTML snapshot, not an offline archive:
  browser resources must remain accessible, and DOM properties such as unsaved
  input values, canvas contents, and shadow roots are not serialized.

  The temporary file remains available after the session closes.

      session
      |> visit("/chamber")
      |> open_browser()
  """
  @spec open_browser(Session.t()) :: Session.t()
  def open_browser(%Session{} = session), do: open_browser(session, &Fluffy.OpenBrowser.open/1)

  @doc false
  @spec open_browser(Session.t(), (String.t() -> term())) :: Session.t()
  def open_browser(%Session{} = session, open_fun) when is_function(open_fun, 1) do
    if Session.current_driver(session) == :unvisited do
      raise ArgumentError, "visit a page before calling open_browser/1"
    end

    dispatch_driver(session, :open_browser, [open_fun])
  end

  @doc false
  def session_for_html(driver, html, options \\ [])

  def session_for_html(:static, html, _options) do
    Backend.static_html_session(html)
  end

  def session_for_html(:playwright, html, options) do
    start_session =
      if Fluffy.TestScope.current() do
        &Backend.start_session/2
      else
        &Backend.start_unmanaged_session/2
      end

    :playwright
    |> start_session.(options)
    |> Backend.visit("/harness")
    |> set_html(html)
  end

  @doc group: "Lifecycle and navigation"
  def visit(%Session{} = session, path), do: Backend.visit(session, path)

  @doc group: "Lifecycle and navigation"
  @doc """
  Reloads the active page's current document and returns the updated session.

  The Phoenix backend re-dispatches the current URL and selects the Static or
  LiveView driver for the returned page. The Playwright backend asks the active
  browser page to reload.
  """
  @spec reload(Session.t(), [action_option()]) :: Session.t()
  def reload(%Session{} = session, options \\ []) do
    options = Fluffy.Options.validate_action!(options)
    Backend.reload(session, options)
  end

  @doc group: "Diagnostics and native access"
  @doc """
  Runs a driver-specific native operation and returns the reconciled session.

  Static callbacks receive the current `Plug.Conn` and must return an updated
  `Plug.Conn`. LiveView callbacks receive the current
  `Phoenix.LiveViewTest.View`, and Playwright callbacks receive a
  `Fluffy.Playwright.Handle`. Successful LiveView and Playwright callback return
  values are ignored.

  Native operations are not cross-driver compatible. Prefer the shared
  Fluffy API whenever it covers the behavior under test.
  """
  def unwrap(%Session{} = session, fun) when is_function(fun, 1) do
    case Session.current_driver(session) do
      :unvisited ->
        raise ArgumentError,
              "cannot unwrap a Phoenix session before its first visit has classified the page"

      _driver ->
        dispatch_driver(session, :unwrap, [fun])
    end
  end

  @doc group: "Events"
  @doc "Registers an event wait immediately. Await the pending handle once with `await/1`."
  @spec wait_for(Session.t(), Event.t(), [Event.option()]) :: Pending.t()
  def wait_for(%Session{} = session, %Event{} = event, options \\ []), do: Event.wait(session, event, options)

  @doc group: "Events"
  @doc "Consumes a pending event and returns its value. Its deadline starts at registration."
  @spec await(Pending.t()) :: term()
  defdelegate await(pending), to: Pending

  @doc group: "Events"
  @doc "Registers a persistent handler. Handlers run independently, linked to the registering caller."
  def on(%Session{} = session, %Event{} = event, handler, options \\ []),
    do: Event.listen(session, event, handler, options, :on)

  @doc group: "Events"
  @doc "Registers a handler for the first matching event, removing it before invocation."
  def once(%Session{} = session, %Event{} = event, handler, options \\ []),
    do: Event.listen(session, event, handler, options, :once)

  @doc group: "Events"
  @doc "Removes the most recently registered listener matching this source, event type, and handler."
  def off(%Session{} = session, %Event{} = event, handler, options \\ []), do: Event.off(session, event, handler, options)

  @doc group: "Lifecycle and navigation"
  @doc "Returns a live handle to the selected page."
  @spec current_page(Session.t()) :: Fluffy.Page.t()
  def current_page(%Session{} = session) do
    Session.current_driver(session)
    Session.handle(session)
  end

  @doc group: "Lifecycle and navigation"
  @doc "Selects a page handle for this pipeline, without changing other session handles."
  @spec switch_page(Session.t(), Fluffy.Page.t()) :: Session.t()
  def switch_page(%Session{} = session, %Fluffy.Page{} = page), do: Session.activate_page(session, page)

  @doc group: "Lifecycle and navigation"
  @doc "Closes a page. Handles selecting it must explicitly switch to another page before continuing."
  @spec close_page(Session.t()) :: Session.t()
  def close_page(%Session{} = session), do: close_page(session, Session.handle(session))

  @doc group: "Lifecycle and navigation"
  @doc "Closes the given page handle, preserving the session's current-page selection."
  @spec close_page(Session.t(), Fluffy.Page.t()) :: Session.t()
  def close_page(%Session{} = session, %Fluffy.Page{} = page), do: Backend.close_page(session, page)

  @doc group: "Lifecycle and navigation"
  @doc "Returns live handles for all open pages, including browser pages discovered without an event wait."
  @spec pages(Session.t()) :: [Fluffy.Page.t()]
  def pages(%Session{} = session) do
    Enum.map(Session.pages(session), fn {id, _page} -> Fluffy.Page.new(session.runtime, id) end)
  end

  @doc false
  def __expect__(session, expectation), do: dispatch_driver(session, :expect, [expectation])

  @doc false
  def set_html(%Session{} = session, html) do
    dispatch_driver(session, :set_html, [html])
  end

  @doc group: "Actions"
  @spec click(Session.t(), Fluffy.Locator.t(), [action_option()]) :: Session.t()
  def click(%Session{} = session, locator, options \\ []) do
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :click, [locator, options])
  end

  @doc group: "Actions"
  @doc """
  Submits one form through its native submission path.

  This is a semantic form action, not a synthetic keyboard event. Clicking a
  particular submit button remains the way to select a submitter and its
  `name`/`value` or override attributes.

  Playwright follows browser-native constraint validation. Static and LiveView
  deliberately bypass it and submit the current structural form state; use
  Playwright when the test concerns invalid events, validity UI, focus, or
  browser-blocked submission.
  """
  @spec submit(Session.t(), Fluffy.Locator.t(), [action_option()]) :: Session.t()
  def submit(%Session{} = session, locator, options \\ []) do
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :submit, [locator, options])
  end

  @doc group: "Actions"
  @doc """
  Fills a control with the literal string representation of `value`.

  Accepts any value implementing `String.Chars`, including numbers, dates,
  and custom structs. Conversion uses `to_string/1`, without HTML escaping.
  """
  @spec fill(Session.t(), Fluffy.Locator.t(), String.Chars.t(), [action_option()]) :: Session.t()
  def fill(%Session{} = session, locator, value, options \\ []) do
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :fill, [locator, to_string(value), options])
  end

  @doc group: "Actions"
  @doc """
  Selects local paths or in-memory `Fluffy.FilePayload` values for a file
  input, or clears its FileList with `[]`.

  One path or payload selects one file. A non-empty homogeneous list selects
  files in list order on an input with the `multiple` attribute. `[]` clears
  the current selection. The complete value is validated and snapshotted
  before the page changes. Static and LiveView drivers carry those snapshots
  into form submission or the supported managed-upload lifecycle; Playwright
  uses its native path or payload transport.

  The default aggregate selection limit is configured with
  `config :fluffy, file_input_max_bytes: 10_000_000`. Override it for one
  action with `:max_bytes`. File contents are never included in size or
  validation errors.

  Pass a chooser returned by `Fluffy.Event.file_chooser/1` directly. It targets
  its original page and preserves the session's current-page selection. Choosers
  require Playwright. The returned session keeps this action pipeable:

      pending = wait_for(session, Fluffy.Event.file_chooser())

      session
      |> click(by_role(:button, name: "Upload"))
      |> set_input_files(await(pending), "test/fixtures/report.pdf")
      |> click(by_role(:button, name: "Save"))

  Register the wait before clicking the button. `await/1` returns the chooser;
  `set_input_files/4` fills its input and returns the session.

  ## Options

  #{NimbleOptions.docs(Fluffy.Options.file_input_schema())}
  """
  @spec set_input_files(
          Session.t(),
          Fluffy.Locator.t() | Fluffy.FileChooser.t(),
          String.t() | Fluffy.FilePayload.t() | [String.t()] | [Fluffy.FilePayload.t()],
          [file_input_option()]
        ) :: Session.t()
  def set_input_files(%Session{} = session, locator_or_chooser, selection, options \\ []) do
    options = Fluffy.Options.validate_file_input!(options)

    max_bytes =
      Keyword.get(
        options,
        :max_bytes,
        Application.get_env(:fluffy, :file_input_max_bytes, 10_000_000)
      )

    {source, selected_files} = SelectedFile.prepare!(selection, max_bytes: max_bytes)
    driver_options = Keyword.delete(options, :max_bytes)

    target_session =
      case locator_or_chooser do
        %Fluffy.FileChooser{page: page} -> Session.activate_page(session, page)
        _locator -> session
      end

    result =
      dispatch_driver(
        target_session,
        :set_input_files,
        [locator_or_chooser, source, selected_files, driver_options]
      )

    %{result | active_page: session.active_page}
  end

  @doc group: "Actions"
  @spec check(Session.t(), Fluffy.Locator.t(), [action_option()]) :: Session.t()
  def check(%Session{} = session, locator, options \\ []) do
    set_checked(session, locator, true, options)
  end

  @doc group: "Actions"
  @spec uncheck(Session.t(), Fluffy.Locator.t(), [action_option()]) :: Session.t()
  def uncheck(%Session{} = session, locator, options \\ []) do
    set_checked(session, locator, false, options)
  end

  @doc group: "Actions"
  @doc """
  Selects options by value or label, or explicitly with `%{value: value}`,
  `%{label: label}`, or `%{index: index}`.

  Values and labels accept `String.Chars` and are converted without HTML
  escaping. Indexes remain zero-based integers. A list requests multiple
  options; wrap a charlist in `%{value: charlist}` or `%{label: charlist}`
  to use it as one option.
  """
  @spec select_option(Session.t(), Fluffy.Locator.t(), term(), [action_option()]) :: Session.t()
  def select_option(%Session{} = session, locator, requested, options \\ []) do
    options = Fluffy.Options.validate_action!(options)
    requested = if is_list(requested), do: requested, else: [requested]
    requested = Enum.map(requested, &stringify_option/1)
    dispatch_driver(session, :select_option, [locator, requested, options])
  end

  defp stringify_option(value) when is_struct(value), do: to_string(value)
  defp stringify_option(%{value: value} = option), do: %{option | value: to_string(value)}
  defp stringify_option(%{label: label} = option), do: %{option | label: to_string(label)}
  defp stringify_option(%{index: _index} = option), do: option
  defp stringify_option(value), do: to_string(value)

  @doc group: "Actions"
  @spec focus(Session.t(), Fluffy.Locator.t(), [action_option()]) :: Session.t()
  def focus(%Session{} = session, locator, options \\ []) do
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :focus, [locator, options])
  end

  @doc group: "Actions"
  @spec blur(Session.t(), Fluffy.Locator.t(), [action_option()]) :: Session.t()
  def blur(%Session{} = session, locator, options \\ []) do
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :blur, [locator, options])
  end

  @doc group: "Actions"
  @doc """
  Presses `Enter`, `Space`, or `Tab` on one strict target.

  On a LiveView page, direct or window `phx-keydown`/`phx-keyup` bindings and
  `phx-key` filters are dispatched with their browser-shaped key and current
  value payload before and around the supported structural default action.
  Plain event names and push-only `Phoenix.LiveView.JS` bindings are portable;
  client-side JS commands, custom LiveSocket metadata, modifiers, key repeat,
  and timing assertions require Playwright.

  `press(locator, "Enter")` means the browser's implicit Enter behavior. Use
  `submit/2` when the intent is simply to submit a form.
  """
  @spec press(Session.t(), Fluffy.Locator.t(), String.t(), [action_option()]) :: Session.t()
  def press(%Session{} = session, locator, key, options \\ []) when is_binary(key) do
    options = Fluffy.Options.validate_action!(options)

    if key not in @shared_press_keys do
      raise ArgumentError,
            "unsupported key #{inspect(key)}; the shared press subset is Enter, Space, and Tab"
    end

    dispatch_driver(session, :press, [locator, key, options])
  end

  defp set_checked(%Session{} = session, locator, desired, options) do
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :set_checked, [locator, desired, options])
  end

  defp dispatch_driver(%Session{} = session, operation, arguments) do
    driver = DriverRegistry.module(Session.current_driver(session))
    driver.validate_operation!(session, operation, arguments)

    result =
      apply(driver, operation, [
        session | arguments
      ])

    resolve_driver_result(result, operation, arguments)
  rescue
    error ->
      stacktrace = __STACKTRACE__
      error = Backend.normalize_error(session, operation, arguments, error)

      Backend.capture_failure(session, operation, error, stacktrace)

      reraise(error, stacktrace)
  end

  defp resolve_driver_result(%Session{} = session, _operation, _arguments), do: session

  defp resolve_driver_result({:navigate, %Session{} = session, navigation}, _operation, _arguments) do
    Backend.navigate(session, navigation)
  end

  defp resolve_driver_result({:navigate, %Session{} = session, navigation, {:retry, remaining}}, operation, arguments) do
    session
    |> Backend.navigate(navigation)
    |> dispatch_driver(operation, put_retry_timeout(arguments, remaining))
  end

  defp put_retry_timeout(arguments, remaining) do
    List.update_at(arguments, -1, fn
      %Expect{} = expectation -> Expect.merge_options(expectation, timeout: remaining)
      options -> Keyword.put(options, :timeout, remaining)
    end)
  end
end
