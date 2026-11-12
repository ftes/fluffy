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

      start_session(:phoenix)
      |> visit("/creatures/new")
      |> fill(by_label("Name"), "Basilisk")
      |> click(by_role(:button, name: "Register"))
      |> assert(visible(by_text("Creature registered")))

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
  alias Fluffy.SelectedFile
  alias Fluffy.Session

  @native_values [Fluffy.Route, Fluffy.Download, Fluffy.FileChooser]

  @typedoc "A browser value that `unwrap_and_return/2` resolves to its PlaywrightEx counterpart."
  @type native_value :: Fluffy.Route.t() | Fluffy.Download.t() | Fluffy.FileChooser.t()

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
  @type wait_for_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:wait_for)))
  @type click_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:click)))
  @type fill_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:fill)))
  @type clear_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:clear)))
  @type check_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:check)))
  @type uncheck_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:uncheck)))
  @type set_checked_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:set_checked)))
  @type select_option_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:select_option)))
  @type press_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:press)))
  @type reload_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.action_schema(:reload)))
  @type file_input_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.file_input_schema()))
  @type session_option ::
          unquote(NimbleOptions.option_typespec(Fluffy.Options.session_schema()))

  @spec start_session(backend(), [session_option()]) :: Session.t()
  def start_session(backend, options \\ []), do: Backend.start_session(backend, options)

  @doc group: "Lifecycle and navigation"
  @doc "Closes a session and its resources. Returns `:ok`."
  @spec close_session(Session.t()) :: :ok
  def close_session(%Session{} = session), do: Backend.close_session(session)

  @doc group: "Diagnostics and native access"
  @doc """
  Opens a temporary HTML snapshot of the active page in your default browser.

  Returns the unchanged session so it can be used in a pipeline. Static and
  LiveView pages resolve local assets through the session endpoint; LiveView
  snapshots show the full page, including the root layout and portal content.
  Playwright pages resolve assets against the page URL. Scripts are removed. This is an HTML snapshot, not an offline archive:
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
    :playwright
    |> Backend.start_session(options)
    |> Backend.visit("/harness")
    |> set_html(html)
  end

  @doc group: "Lifecycle and navigation"
  @doc """
  Navigates the active page to `path` and returns the updated session.

  The Phoenix backend selects the Static or LiveView driver for the returned page.
  """
  def visit(%Session{} = session, path), do: Backend.visit(session, path)

  @doc group: "Lifecycle and navigation"
  @doc """
  Reloads the active page's current document and returns the updated session.

  The Phoenix backend re-dispatches the current URL and selects the Static or
  LiveView driver for the returned page. The Playwright backend asks the active
  browser page to reload.

  ## Options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:reload)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:reload))}
  """
  @spec reload(Session.t(), [reload_option()]) :: Session.t()
  def reload(%Session{} = session, options \\ []) do
    options = Fluffy.Options.validate_action!(:reload, options)
    Backend.reload(session, options)
  end

  @doc group: "Diagnostics and native access"
  @doc """
  Runs a driver-specific native operation with the session's native counterpart
  and returns the reconciled session. Static callbacks receive the current
  `Plug.Conn` and must return an updated `Plug.Conn`. LiveView callbacks
  receive the current `Phoenix.LiveViewTest.View`, and Playwright callbacks
  receive the `PlaywrightEx.Page`. Successful LiveView and Playwright callback
  return values are ignored; `unwrap_and_return/2` returns the callback's
  result instead of the session. `Fluffy.Playwright.unwrap/3` passes a native
  locator instead. For the native value of a `Fluffy.Download`, use
  `unwrap_and_return/2`.

  Native operations are not cross-driver compatible. Prefer the shared
  Fluffy API whenever it covers the behavior under test.
  """
  @spec unwrap(Session.t(), (term() -> term())) :: Session.t()
  def unwrap(%Session{} = session, fun) when is_function(fun, 1), do: dispatch_unwrap(session, :unwrap, fun)

  defp dispatch_unwrap(session, operation, fun) do
    case Session.current_driver(session) do
      :unvisited ->
        raise ArgumentError,
              "cannot unwrap a Phoenix session before its first visit has classified the page"

      _driver ->
        dispatch_driver(session, operation, [fun])
    end
  end

  @doc group: "Diagnostics and native access"
  @doc """
  Runs `fun` with the session's native counterpart, like `unwrap/2`, and returns
  the callback's result instead of the session.

      html = unwrap_and_return(session, &Phoenix.LiveViewTest.render/1)
      title = unwrap_and_return(session, &PlaywrightEx.Page.title!/1)

  LiveView and Playwright reconcile as `unwrap/2` does, following redirects and
  navigation the callback causes, so keep using the same session afterwards. A
  Static callback may return anything: its `Plug.Conn` is not replaced and the
  page stays as it is. `Fluffy.Playwright.unwrap_and_return/3` passes a native
  locator instead.

  With a `Fluffy.Route`, `Fluffy.Download` or `Fluffy.FileChooser`, `fun` receives its
  PlaywrightEx counterpart. A Phoenix download has none and raises `Fluffy.CapabilityError`.
  Other events deliver PlaywrightEx's values themselves.

      path = unwrap_and_return(download, &PlaywrightEx.Download.path!/1)
  """
  @spec unwrap_and_return(Session.t(), (term() -> result)) :: result when result: term()
  @spec unwrap_and_return(native_value(), (term() -> result)) :: result when result: term()
  def unwrap_and_return(%Session{} = session, fun) when is_function(fun, 1),
    do: dispatch_unwrap(session, :unwrap_and_return, fun)

  def unwrap_and_return(%module{} = value, fun) when module in @native_values and is_function(fun, 1),
    do: fun.(native!(value))

  defp native!(%Fluffy.Download{native: nil}) do
    raise Fluffy.CapabilityError,
      capability: :native_download,
      driver: :phoenix,
      detail: "a Phoenix download has no native counterpart"
  end

  # A value such as a download outlives its page but not its session.
  defp native!(%{native: native} = value) when is_struct(native) do
    if page = owner_page(value), do: Fluffy.Page.ensure_session!(page)
    native
  end

  defp native!(value), do: raise(ArgumentError, "#{inspect(value.__struct__)} has no native counterpart")

  defp owner_page(%{page: page}), do: page
  defp owner_page(_value), do: nil

  @doc group: "Events"
  @doc """
  Waits for an event or a locator.

  With a `Fluffy.Event`, registers the wait immediately and returns a pending
  handle: await it once with `await/1`.

  With a `Fluffy.Locator`, blocks until the locator reaches `state:`, by default
  `:visible`, and returns the session. This form is Playwright only, and raises
  `Fluffy.CapabilityError` on Phoenix. It raises after the session's `timeout:` unless
  `timeout:` is given. Prefer an `expect` when asserting what the page shows.

      session |> wait_for(by_role(:dialog), state: :hidden) |> click(by_role(:button))

  ## Locator options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:wait_for)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:wait_for))}
  """
  @spec wait_for(Session.t(), Event.t(), [Event.option()]) :: Pending.t()
  @spec wait_for(Session.t(), Fluffy.Locator.t(), [wait_for_option()]) :: Session.t()
  def wait_for(session, target, options \\ [])

  def wait_for(%Session{} = session, %Event{} = event, options), do: Event.wait(session, event, options)

  def wait_for(%Session{} = session, %Fluffy.Locator{} = locator, options) do
    Fluffy.Playwright.__ensure_playwright_backend__!(session, :wait_for)
    dispatch_driver(session, :wait_for, [locator, Fluffy.Options.validate_action!(:wait_for, options)])
  end

  @doc group: "Events"
  @doc "Consumes a pending event and returns its value. Its deadline starts at registration."
  @spec await(Pending.t()) :: term()
  defdelegate await(pending), to: Pending

  @doc group: "Events"
  @doc "Registers a persistent handler. Handlers run independently, linked to the registering caller."
  @spec on(Session.t(), Event.t(), (term() -> term()), [{:scope, :page | :context}]) :: Session.t()
  def on(%Session{} = session, %Event{} = event, handler, options \\ []),
    do: Event.listen(session, event, handler, options, :on)

  @doc group: "Events"
  @doc "Registers a handler for the first matching event, removing it before invocation."
  @spec once(Session.t(), Event.t(), (term() -> term()), [{:scope, :page | :context}]) :: Session.t()
  def once(%Session{} = session, %Event{} = event, handler, options \\ []),
    do: Event.listen(session, event, handler, options, :once)

  @doc group: "Events"
  @doc "Removes the most recently registered listener matching this source, event type, and handler."
  @spec off(Session.t(), Event.t(), (term() -> term()), [{:scope, :page | :context}]) :: Session.t()
  def off(%Session{} = session, %Event{} = event, handler, options \\ []), do: Event.off(session, event, handler, options)

  @doc false
  def __expect__(session, expectation), do: dispatch_driver(session, :expect, [expectation])

  @doc false
  def set_html(%Session{} = session, html) do
    dispatch_driver(session, :set_html, [html])
  end

  @doc group: "Actions"
  @doc """
  Clicks one strict target.

  ## Options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:click)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:click))}
  """
  @spec click(Session.t(), Fluffy.Locator.t(), [click_option()]) :: Session.t()
  def click(%Session{} = session, locator, options \\ []) do
    options = Fluffy.Options.validate_action!(:click, options)
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

  Filling contenteditable elements requires Playwright. Static and LiveView
  support input and textarea controls.

  ## Options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:fill)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:fill))}
  """
  @spec fill(Session.t(), Fluffy.Locator.t(), String.Chars.t(), [fill_option()]) :: Session.t()
  def fill(%Session{} = session, locator, value, options \\ []) do
    options = Fluffy.Options.validate_action!(:fill, options)
    dispatch_driver(session, :fill, [locator, to_string(value), options])
  end

  @doc group: "Actions"
  @doc """
  Clears a text input or textarea, like `fill/4` with an empty string.

  ## Options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:clear)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:clear))}
  """
  @spec clear(Session.t(), Fluffy.Locator.t(), [clear_option()]) :: Session.t()
  def clear(%Session{} = session, locator, options \\ []) do
    options = Fluffy.Options.validate_action!(:clear, options)
    dispatch_driver(session, :clear, [locator, options])
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
      |> set_input_files(await(pending), "test/fixtures/homework.pdf")
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
  @doc """
  Checks a checkbox or radio.

  ## Options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:check)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:check))}
  """
  @spec check(Session.t(), Fluffy.Locator.t(), [check_option()]) :: Session.t()
  def check(%Session{} = session, locator, options \\ []) do
    options = Fluffy.Options.validate_action!(:check, options)
    dispatch_driver(session, :set_checked, [locator, true, options])
  end

  @doc group: "Actions"
  @doc """
  Unchecks a checkbox.

  ## Options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:uncheck)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:uncheck))}
  """
  @spec uncheck(Session.t(), Fluffy.Locator.t(), [uncheck_option()]) :: Session.t()
  def uncheck(%Session{} = session, locator, options \\ []) do
    options = Fluffy.Options.validate_action!(:uncheck, options)
    dispatch_driver(session, :set_checked, [locator, false, options])
  end

  @doc group: "Actions"
  @doc """
  Sets a checkbox or radio to `checked`, like `check/3` or `uncheck/3` chosen at runtime.

  ## Options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:set_checked)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:set_checked))}
  """
  @spec set_checked(Session.t(), Fluffy.Locator.t(), boolean(), [set_checked_option()]) :: Session.t()
  def set_checked(%Session{} = session, locator, checked, options \\ []) when is_boolean(checked) do
    options = Fluffy.Options.validate_action!(:set_checked, options)
    dispatch_driver(session, :set_checked, [locator, checked, options])
  end

  @doc group: "Actions"
  @doc """
  Selects options by value or label, or explicitly with `%{value: value}`,
  `%{label: label}`, or `%{index: index}`.

  Values and labels accept `String.Chars` and are converted without HTML
  escaping. Indexes remain zero-based integers. A list requests multiple
  options; wrap a charlist in `%{value: charlist}` or `%{label: charlist}`
  to use it as one option. As in Playwright, a list is either all values and
  labels or all option maps; a mixed list raises `ArgumentError`.

  ## Options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:select_option)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:select_option))}
  """
  @spec select_option(Session.t(), Fluffy.Locator.t(), term(), [select_option_option()]) :: Session.t()
  def select_option(%Session{} = session, locator, requested, options \\ []) do
    options = Fluffy.Options.validate_action!(:select_option, options)
    requested = if is_list(requested), do: requested, else: [requested]
    requested = Enum.map(requested, &stringify_option/1)

    # Playwright types the whole list by its first element.
    if !(Enum.all?(requested, &is_binary/1) or Enum.all?(requested, &is_map/1)) do
      raise ArgumentError,
            "select_option/4 takes a list of values and labels or a list of option maps, not both: " <>
              inspect(requested)
    end

    dispatch_driver(session, :select_option, [locator, requested, options])
  end

  defp stringify_option(value) when is_struct(value), do: to_string(value)
  defp stringify_option(%{value: value} = option), do: %{option | value: to_string(value)}
  defp stringify_option(%{label: label} = option), do: %{option | label: to_string(label)}
  defp stringify_option(%{index: _index} = option), do: option
  defp stringify_option(value), do: to_string(value)

  @doc group: "Actions"
  @doc """
  Presses a key on one strict target. Behavior depends on the current driver.

  Playwright performs a native key press, including browser default actions,
  and accepts Playwright key names, characters, and modifier combinations.

  LiveView sends `%{"key" => key}`, with the element's values and `phx-target`
  as LiveView's client sends them, to bindings on the selected element; as
  there, a `phx-value-key` wins over the pressed key. Either or both phases may be bound, including `phx-window-keydown` and
  `phx-window-keyup` on that element. An element with no keyboard binding, or a
  disabled one, raises. Fluffy does not filter
  `phx-key`, translate key names, parse modifier combinations, synthesize input
  values, change focus, edit text, activate controls, or submit forms.
  The caller is responsible for supplying the intended key value.

  Static pages do not support `press` and raise `Fluffy.CapabilityError`.
  Use `submit/2` to submit a form explicitly on any driver.

  ## Options

  Playwright-only options pass through to #{Fluffy.Options.native_reference(:press)}.

  #{NimbleOptions.docs(Fluffy.Options.action_schema(:press))}
  """
  @spec press(Session.t(), Fluffy.Locator.t(), String.t(), [press_option()]) :: Session.t()
  def press(%Session{} = session, locator, key, options \\ []) when is_binary(key) do
    options = Fluffy.Options.validate_action!(:press, options)

    dispatch_driver(session, :press, [locator, key, options])
  end

  @doc false
  def __dispatch_driver__(session, operation, arguments), do: dispatch_driver(session, operation, arguments)

  defp dispatch_driver(%Session{} = session, operation, arguments) do
    driver = DriverRegistry.module(Session.current_driver(session))
    driver.validate_operation!(session, operation, arguments)

    result =
      apply(driver, operation, [
        session | arguments
      ])

    resolve_driver_result(result)
  rescue
    error -> reraise(Backend.normalize_error(session, operation, arguments, error), __STACKTRACE__)
  end

  defp resolve_driver_result(%Session{} = session), do: session

  defp resolve_driver_result({:return, result, outcome}) do
    resolve_driver_result(outcome)
    result
  end

  defp resolve_driver_result({:navigate, %Session{} = session, navigation}) do
    Backend.navigate(session, navigation)
  end
end
