defmodule Fluffy do
  @moduledoc """
  Pipeable feature testing for Phoenix applications.

  Start a session with the Phoenix (`:phoenix`) or Playwright (`:playwright`)
  backend, then compose locators, actions, expectations, and event capture.
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
               "Event capture and results",
               "Diagnostics and native access"
             ]

  alias Fluffy.Backend
  alias Fluffy.Driver.Registry, as: DriverRegistry
  alias Fluffy.Event
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

  # Session is deliberately opaque to consumers, while this public facade is
  # one of the modules that implements that handle. Dialyzer in Elixir 1.18
  # has no friend-module concept and otherwise rejects every annotated facade
  # function whose implementation matches the private struct.
  @dialyzer {:nowarn_function,
             reload: 2,
             page: 2,
             click: 3,
             submit: 3,
             fill: 4,
             set_input_files: 4,
             check: 3,
             uncheck: 3,
             select_option: 4,
             focus: 3,
             blur: 3,
             press: 4}

  @spec start_session(backend(), [session_option()]) :: Session.t()
  def start_session(backend, options \\ []), do: Backend.start_session(backend, options)

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

  @doc group: "Event capture and results"
  @doc """
  Captures an event caused by `action` and stores the normalized result under
  the event's key.

  The listener is installed before the action runs. The returned session keeps
  the captured result so the call remains pipeable.
  """
  # Session is consumer-opaque but passed through internal event orchestration.
  # Dialyzer has no friend-module concept for that callback boundary.
  @dialyzer {:nowarn_function, wait_for: 4}
  @spec wait_for(Session.t(), Event.t(), (Session.t() -> Session.t()), [Event.option()]) :: Session.t()
  def wait_for(%Session{} = session, %Event{} = event, action, options \\ []) when is_function(action, 1) do
    event = Event.merge_options(event, options)
    validate_event!(event)
    Event.capture(session, event.type, event.key, action, event.options)
  end

  @doc group: "Event capture and results"
  @doc "Returns a previously captured download without consuming it."
  def download(%Session{} = session, key), do: Session.fetch_result!(session, key, :download)

  @doc group: "Event capture and results"
  @doc "Returns a previously captured file chooser without consuming it."
  def file_chooser(%Session{} = session, key), do: Session.fetch_result!(session, key, :file_chooser)

  @doc group: "Event capture and results"
  @doc "Returns a previously captured navigation without consuming it."
  def navigation(%Session{} = session, key), do: Session.fetch_result!(session, key, :navigation)

  @doc group: "Event capture and results"
  @doc "Returns a previously captured `Fluffy.Page` without consuming it."
  @spec page(Session.t(), term()) :: Fluffy.Page.t()
  def page(%Session{} = session, name), do: Session.fetch_result!(session, name, :page)

  @doc group: "Lifecycle and navigation"
  @doc "Makes a named Playwright page the target of subsequent actions and assertions."
  def switch_page(%Session{} = session, name), do: Backend.activate_page(session, name)

  @doc group: "Lifecycle and navigation"
  @doc "Closes a named Playwright page, or the active page when no name is supplied."
  def close_page(%Session{} = session, name \\ nil) do
    Backend.close_page(session, name || session.active_page)
  end

  @doc group: "Lifecycle and navigation"
  @doc "Returns all current session-local page names."
  def page_names(%Session{} = session), do: Map.keys(session.pages)

  @doc group: "Event capture and results"
  @doc "Returns a previously captured dialog without consuming it."
  def dialog(%Session{} = session, key), do: Session.fetch_result!(session, key, :dialog)

  @doc group: "Event capture and results"
  @doc "Returns a previously captured request without consuming it."
  def request(%Session{} = session, key), do: Session.fetch_result!(session, key, :request)

  @doc group: "Event capture and results"
  @doc "Returns a previously captured response without consuming it."
  def response(%Session{} = session, key), do: Session.fetch_result!(session, key, :response)

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
  @spec fill(Session.t(), Fluffy.Locator.t(), String.t(), [action_option()]) :: Session.t()
  def fill(%Session{} = session, locator, value, options \\ []) do
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :fill, [locator, value, options])
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

  When `locator_or_chooser` is an atom, it names a chooser previously captured
  with `Fluffy.Event.file_chooser/2`. Chooser-key selection is available only
  in Playwright sessions.

  ## Options

  #{NimbleOptions.docs(Fluffy.Options.file_input_schema())}
  """
  @spec set_input_files(
          Session.t(),
          Fluffy.Locator.t() | atom(),
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

    dispatch_driver(
      session,
      :set_input_files,
      [locator_or_chooser, source, selected_files, driver_options]
    )
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
  @spec select_option(Session.t(), Fluffy.Locator.t(), term(), [action_option()]) :: Session.t()
  def select_option(%Session{} = session, locator, requested, options \\ []) do
    options = Fluffy.Options.validate_action!(options)
    dispatch_driver(session, :select_option, [locator, requested, options])
  end

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

  defp validate_event!(%Event{type: :dialog, options: options}) do
    options |> Keyword.fetch!(:decision) |> validate_dialog_decision!()
  end

  defp validate_event!(%Event{type: type, options: options}) when type in [:request, :response] do
    options |> Keyword.fetch!(:matcher) |> validate_network_matcher!()
  end

  defp validate_event!(%Event{}), do: :ok

  defp dispatch_driver(%Session{} = session, operation, arguments) do
    result =
      apply(DriverRegistry.module(Session.current_driver(session)), operation, [
        session | arguments
      ])

    resolve_driver_result(result, operation, arguments)
  rescue
    error ->
      stacktrace = __STACKTRACE__

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

  defp validate_dialog_decision!(decision) when decision in [:accept, :dismiss] or is_function(decision, 1), do: :ok

  defp validate_dialog_decision!({:accept, prompt_text}) when is_binary(prompt_text), do: :ok

  defp validate_dialog_decision!(decision) do
    raise ArgumentError,
          "dialog decision must be :accept, :dismiss, {:accept, prompt_text}, or a one-argument function; got: #{inspect(decision)}"
  end

  defp validate_network_matcher!(matcher) when is_binary(matcher) or is_struct(matcher, Regex) or is_function(matcher, 1),
    do: :ok

  defp validate_network_matcher!(matcher) do
    raise ArgumentError,
          "network event matcher must be a URL string, Regex, or a one-argument function; got: #{inspect(matcher)}"
  end
end
