defmodule Fluffy.Playwright do
  @moduledoc """
  Browser-only helpers for the active Playwright page.

  These functions intentionally live under `Fluffy.Playwright` because they
  depend on a real browser. Use them when behavior requires one; they are not
  implemented by the Static or LiveView drivers. The page clock lives in
  `Fluffy.Playwright.Clock`.
  """

  alias Fluffy.Backend
  alias Fluffy.Backend.Playwright, as: PlaywrightBackend
  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.CapabilityError
  alias Fluffy.Options
  alias Fluffy.Playwright.Trace
  alias Fluffy.Session
  alias PlaywrightEx.BrowserContext

  @trace_schema NimbleOptions.new!(
                  directory: [
                    type: :string,
                    doc: "Directory in which to save the trace archive."
                  ],
                  name: [
                    type: :string,
                    doc: "Human-readable trace name and artifact filename prefix."
                  ],
                  open: [
                    type: :boolean,
                    default: true,
                    doc: "Open Playwright Trace Viewer after saving the trace."
                  ]
                )

  @trace_capture [screenshots: true, snapshots: true, sources: true]

  @typedoc "Fluffy's trace options, and the capture options of `PlaywrightEx.Tracing.start/2`."
  @type trace_option ::
          unquote(NimbleOptions.option_typespec(@trace_schema))
          | {:screenshots, boolean()}
          | {:snapshots, boolean() | map()}
          | {:sources, boolean()}
          | {:live, boolean()}

  @type go_back_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:go_back)))
  @type go_forward_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:go_forward)))
  @type hover_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:hover)))
  @type drag_to_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:drag_to)))
  @type press_sequentially_option ::
          unquote(NimbleOptions.option_typespec(Options.action_schema(:press_sequentially)))

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Returns a live handle to the selected page."
  @spec current_page(Session.t()) :: Fluffy.Page.t()
  def current_page(%Session{} = session) do
    ensure_playwright_backend!(session, :pages)
    Session.current_driver(session)
    Session.handle(session)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Selects a page handle for this pipeline, without changing other session handles."
  @spec switch_page(Session.t(), Fluffy.Page.t()) :: Session.t()
  def switch_page(%Session{} = session, %Fluffy.Page{} = page) do
    ensure_playwright_backend!(session, :pages)
    Session.activate_page(session, page)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Closes a page. Handles selecting it must explicitly switch to another page before continuing."
  @spec close_page(Session.t()) :: Session.t()
  def close_page(%Session{} = session) do
    ensure_playwright_backend!(session, :pages)
    close_page(session, Session.handle(session))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Closes the given page handle, preserving the session's current-page selection."
  @spec close_page(Session.t(), Fluffy.Page.t()) :: Session.t()
  def close_page(%Session{} = session, %Fluffy.Page{} = page) do
    ensure_playwright_backend!(session, :pages)
    Backend.close_page(session, page)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc "Returns live handles for all open pages, including browser pages discovered without an event wait."
  @spec pages(Session.t()) :: [Fluffy.Page.t()]
  def pages(%Session{} = session) do
    ensure_playwright_backend!(session, :pages)
    Enum.map(Session.pages(session), fn {id, _page} -> Fluffy.Page.new(session.runtime, id) end)
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Creates a blank page in the session's browser context and returns its handle.

  The session keeps its current page selection. Use `switch_page/2` to select
  the new page. Pages share the context's cookies and storage.

      import Fluffy
      import Fluffy.Playwright

      main = current_page(session)
      other = Fluffy.Playwright.new_page(session)

      session
      |> switch_page(other)
      |> visit("/dashboard")
      |> switch_page(main)
  """
  @spec new_page(Session.t()) :: Fluffy.Page.t()
  def new_page(%Session{} = session), do: Backend.new_page(session)

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Navigates backward in browser history. Does nothing if there is no entry.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:go_back)}.

  #{NimbleOptions.docs(Options.action_schema(:go_back))}
  """
  @spec go_back(Session.t(), [go_back_option()]) :: Session.t()
  def go_back(%Session{} = session, options \\ []) do
    ensure_playwright_backend!(session, :browser_history)
    Backend.history(session, :go_back, Options.validate_action!(:go_back, options))
  end

  @doc group: "Lifecycle and navigation"
  @doc playwright_only: true
  @doc """
  Navigates forward in browser history. Does nothing if there is no entry.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:go_forward)}.

  #{NimbleOptions.docs(Options.action_schema(:go_forward))}
  """
  @spec go_forward(Session.t(), [go_forward_option()]) :: Session.t()
  def go_forward(%Session{} = session, options \\ []) do
    ensure_playwright_backend!(session, :browser_history)
    Backend.history(session, :go_forward, Options.validate_action!(:go_forward, options))
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Focuses the target in the active browser page. Accepts `timeout:`."
  @spec focus(Session.t(), Fluffy.Locator.t(), [Fluffy.action_option()]) :: Session.t()
  def focus(%Session{} = session, locator, options \\ []) do
    ensure_playwright_backend!(session, :focus)
    options = Options.validate_action!(:focus, options)
    Fluffy.__dispatch_driver__(session, :focus, [locator, options])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc "Blurs the target in the active browser page. Accepts `timeout:`."
  @spec blur(Session.t(), Fluffy.Locator.t(), [Fluffy.action_option()]) :: Session.t()
  def blur(%Session{} = session, locator, options \\ []) do
    ensure_playwright_backend!(session, :blur)
    options = Options.validate_action!(:blur, options)
    Fluffy.__dispatch_driver__(session, :blur, [locator, options])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Hovers over a locator.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:hover)}.

  #{NimbleOptions.docs(Options.action_schema(:hover))}
  """
  @spec hover(Session.t(), Fluffy.Locator.t(), [hover_option()]) :: Session.t()
  def hover(%Session{} = session, locator, options \\ []) do
    ensure_playwright_backend!(session, :hover)
    Fluffy.__dispatch_driver__(session, :hover, [locator, Options.validate_action!(:hover, options)])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Drags the source locator onto the target locator in the same frame.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:drag_to)}.

  #{NimbleOptions.docs(Options.action_schema(:drag_to))}
  """
  @spec drag_to(Session.t(), Fluffy.Locator.t(), Fluffy.Locator.t(), [drag_to_option()]) :: Session.t()
  def drag_to(%Session{} = session, source, target, options \\ []) do
    ensure_playwright_backend!(session, :drag_to)
    Fluffy.__dispatch_driver__(session, :drag_to, [source, target, Options.validate_action!(:drag_to, options)])
  end

  @doc group: "Actions"
  @doc playwright_only: true
  @doc """
  Types text character by character, emitting keyboard events.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:press_sequentially)}.

  #{NimbleOptions.docs(Options.action_schema(:press_sequentially))}
  """
  @spec press_sequentially(Session.t(), Fluffy.Locator.t(), String.t(), [press_sequentially_option()]) :: Session.t()
  def press_sequentially(%Session{} = session, locator, text, options \\ []) do
    ensure_playwright_backend!(session, :press_sequentially)
    options = Options.validate_action!(:press_sequentially, options)
    Fluffy.__dispatch_driver__(session, :press_sequentially, [locator, text, options])
  end

  @doc playwright_only: true
  @doc """
  Runs `fun` with the `PlaywrightEx.Locator` for `locator` and returns the reconciled session.

  Like `Fluffy.unwrap/2`, for native locator operations that have no Fluffy
  API. The locator resolves in the active page, through any frame locators, and
  is not checked for strictness until the callback uses it. The callback's
  return value is ignored, and a document it navigates is adopted.

      session
      |> Fluffy.Playwright.unwrap(by_role(:button, name: "Edit"), &PlaywrightEx.Locator.dblclick!/1)
      |> expect(to_be_visible(by_label("Title")))

  Prefer PlaywrightEx bang functions inside the callback when failure should
  stop the test. Phoenix sessions raise `Fluffy.CapabilityError`.
  """
  @spec unwrap(Session.t(), Fluffy.Locator.t(), (PlaywrightEx.Locator.t() -> term())) :: Session.t()
  def unwrap(%Session{} = session, %Fluffy.Locator{} = locator, fun) when is_function(fun, 1) do
    ensure_playwright_backend!(session, :native_locator)
    Fluffy.__dispatch_driver__(session, :unwrap_locator, [locator, fun])
  end

  @doc playwright_only: true
  @doc """
  Starts a Playwright trace for this session's BrowserContext.

  The trace includes every page in the session and is saved when the test's
  lifecycle scope shuts down. Because an explicit trace is primarily a local
  debugging request, its viewer opens by default; pass `open: false` in CI. A
  session may start one trace.

  ## Options

  #{NimbleOptions.docs(@trace_schema)}

  Other options go to `PlaywrightEx.Tracing.start/2`. Fluffy defaults
  `screenshots:`, `snapshots:` and `sources:` to `true`.
  """
  @spec trace(Session.t(), [trace_option()]) :: Session.t()
  def trace(session, options \\ []) when is_list(options) do
    ensure_playwright_backend!(session, :tracing)
    {fluffy_options, capture_options} = Keyword.split(options, Keyword.keys(@trace_schema.schema))
    fluffy_options = NimbleOptions.validate!(fluffy_options, @trace_schema)
    context = Session.context(session)

    if context.trace do
      raise ArgumentError, "this Playwright session is already tracing"
    end

    trace = Trace.start(context, fluffy_options, Keyword.merge(@trace_capture, capture_options))

    :ok = Fluffy.SessionRuntime.register(session.runtime, {:trace, trace}, fn -> Trace.stop(trace) end)

    Session.put_context(session, Map.put(context, :trace, Trace.public_state(trace)))
  end

  @doc playwright_only: true
  @doc """
  Saves a screenshot of the active page and returns the session.

  Accepts the options of `PlaywrightEx.Page.screenshot/2`, such as `full_page:`.
  """
  @spec screenshot(Session.t(), Path.t(), PlaywrightEx.Page.screenshot_options()) :: Session.t()
  def screenshot(session, path, options \\ []) when is_binary(path) and is_list(options) do
    ensure_playwright_backend!(session, :screenshot)
    File.mkdir_p!(Path.dirname(path))
    PlaywrightEx.Page.screenshot!(Session.page_state(session).page, Keyword.put(options, :path, path))
    session
  end

  @doc playwright_only: true
  @doc """
  Evaluates JavaScript in the active Playwright page and returns the value.

  This is `PlaywrightEx.Page.evaluate/3`: the expression is JavaScript source,
  either an expression or a function that receives `arg`. Promises are awaited,
  serializable values return as Elixir terms (objects as maps with string
  keys, JavaScript `null` as `:null`), and JavaScript failures raise. The
  call raises if it does not settle within the session's `timeout:`.

  `evaluate/3` is a browser-only value query, so it returns the evaluated value
  rather than the Fluffy session. Use Elixir's `then/2` when a pipeline needs
  the value and then should continue with the session:

      import Fluffy
      import Fluffy.Playwright
      import Fluffy.Locator
      alias Fluffy.Playwright

      session
      |> then(fn session ->
        title = Playwright.evaluate(session, "document.title")
        assert title == "Potions classroom"
        session
      end)
      |> click(by_role(:button, name: "Continue"))

      Playwright.evaluate(session, "selector => document.querySelector(selector).textContent", "#status")

  Do not use this for JavaScript that owns a navigation, opens a page, starts a
  download, or installs a durable listener. Use the corresponding
  listener-before-action `Fluffy.wait_for/3` event API so lifecycle and
  cleanup remain owned by Fluffy. Reserve `Fluffy.unwrap/2` for uncommon
  page-local operations that have no first-class API.
  """
  @spec evaluate(Session.t(), String.t(), term()) :: term()
  def evaluate(session, expression, arg \\ nil) when is_binary(expression) do
    reject_evaluate_options!(arg)
    ensure_playwright!(session)
    frame = Session.page_state(session).frame
    timeout = Session.timeout(session)
    Bounded.within!(timeout, :evaluate, fn -> PlaywrightEx.Frame.evaluate(frame, expression, arg) end)
  end

  # Fluffy 0.8 took `evaluate(session, expression, timeout: ..., is_function: ..., arg: ...)`;
  # such a list would now reach the page as the argument.
  @evaluate_options [:timeout, :is_function, :arg]

  defp reject_evaluate_options!([_ | _] = arg) do
    if Keyword.keyword?(arg) and Enum.all?(Keyword.keys(arg), &(&1 in @evaluate_options)) do
      raise ArgumentError,
            "evaluate/3 takes the JavaScript argument, not the options #{inspect(Keyword.keys(arg))}; " <>
              "call evaluate(session, expression, arg): a function expression receives arg, " <>
              "and the call is bounded by the session's timeout:"
    end
  end

  defp reject_evaluate_options!(_arg), do: :ok

  @doc playwright_only: true
  @doc """
  Adds cookies to the browser context and returns the session.

  Cookie maps use the keys of `PlaywrightEx.BrowserContext.add_cookies/2`, such as
  `%{name: "token", value: "abc", url: url, httpOnly: true, sameSite: "Lax"}`.
  """
  @spec add_cookies(Session.t(), [map()]) :: Session.t()
  def add_cookies(session, cookies) when is_list(cookies) do
    Enum.each(cookies, &reject_snake_case_cookie_keys!/1)
    session |> browser_context!(:add_cookies) |> BrowserContext.add_cookies!(cookies)
    session
  end

  # Playwright ignores unknown cookie keys, such as the snake_case ones Fluffy 0.8 took.
  @snake_case_cookie_keys %{http_only: :httpOnly, same_site: :sameSite, partition_key: :partitionKey}

  defp reject_snake_case_cookie_keys!(cookie) when is_map(cookie) do
    for {key, _value} <- cookie,
        {snake_case, camel_case} <- @snake_case_cookie_keys,
        key in [snake_case, Atom.to_string(snake_case)] do
      raise ArgumentError, "cookie key #{inspect(key)} is not a Playwright cookie field; use #{inspect(camel_case)}"
    end
  end

  defp reject_snake_case_cookie_keys!(_cookie), do: :ok

  @doc playwright_only: true
  @doc "Returns browser cookies, optionally only those for `urls`. See `PlaywrightEx.BrowserContext.cookies/2`."
  @spec cookies(Session.t(), String.t() | [String.t()] | nil) :: [map()]
  def cookies(session, urls \\ nil) do
    session |> browser_context!(:cookies) |> BrowserContext.cookies!(urls)
  end

  @doc playwright_only: true
  @doc """
  Clears cookies and returns the session.

  Accepts the filters of `PlaywrightEx.BrowserContext.clear_cookies/2`: `name:`, `domain:` and `path:`.
  """
  @spec clear_cookies(Session.t(), BrowserContext.clear_cookies_options()) :: Session.t()
  def clear_cookies(session, options \\ []) do
    session |> browser_context!(:clear_cookies) |> BrowserContext.clear_cookies!(options)
    session
  end

  @doc playwright_only: true
  @doc """
  Returns the context's storage state for reuse as `browser_context: [storage_state: state]`.

  Accepts the options of `PlaywrightEx.BrowserContext.storage_state/2`, such as `path:` and `indexed_db:`.
  """
  @spec storage_state(Session.t(), BrowserContext.storage_state_options()) :: map()
  def storage_state(session, options \\ []) do
    session |> browser_context!(:storage_state) |> BrowserContext.storage_state!(options)
  end

  defp browser_context!(session, operation) do
    ensure_playwright_backend!(session, operation)
    Session.context(session).browser_context
  end

  defp ensure_playwright!(session) do
    case Session.current_driver(session) do
      :playwright ->
        :ok

      driver ->
        raise CapabilityError,
          capability: :javascript_evaluation,
          driver: driver,
          detail:
            "JavaScript evaluation requires an active Playwright page; the current page driver is #{inspect(driver)}"
    end
  end

  @doc false
  def __ensure_playwright_backend__!(session, capability), do: ensure_playwright_backend!(session, capability)

  defp ensure_playwright_backend!(session, capability) do
    if Session.backend(session) != PlaywrightBackend do
      raise CapabilityError,
        capability: capability,
        driver: Session.current_driver(session),
        detail: "#{inspect(capability)} requires a Playwright session"
    end
  end
end
