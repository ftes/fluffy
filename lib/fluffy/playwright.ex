defmodule Fluffy.Playwright do
  @moduledoc """
  Browser-only helpers for the active Playwright page.

  These functions intentionally live under `Fluffy.Playwright` because they
  depend on a real browser. Use them when behavior requires one; they are not
  implemented by the Static or LiveView drivers.
  """

  alias Fluffy.Backend.Playwright, as: PlaywrightBackend
  alias Fluffy.CapabilityError
  alias Fluffy.Playwright.Screenshot
  alias Fluffy.Playwright.Trace
  alias Fluffy.Session
  alias PlaywrightEx.Frame

  @type evaluate_option :: unquote(NimbleOptions.option_typespec(Fluffy.Options.evaluate_schema()))

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
                  ],
                  screenshots: [
                    type: :boolean,
                    default: true,
                    doc: "Capture screenshots during tracing."
                  ],
                  snapshots: [
                    type: :boolean,
                    default: true,
                    doc: "Capture DOM snapshots and network activity."
                  ],
                  sources: [
                    type: :boolean,
                    default: true,
                    doc: "Include source files in the trace."
                  ]
                )

  @type trace_option :: unquote(NimbleOptions.option_typespec(@trace_schema))

  @screenshot_schema NimbleOptions.new!(
                       full_page: [
                         type: :boolean,
                         default: false,
                         doc: "Capture the full scrollable page instead of only the viewport."
                       ],
                       omit_background: [
                         type: :boolean,
                         default: false,
                         doc: "Hide the default white background to allow transparency."
                       ],
                       timeout: [
                         type: :pos_integer,
                         doc: "Maximum screenshot time in milliseconds."
                       ]
                     )

  @type screenshot_option :: unquote(NimbleOptions.option_typespec(@screenshot_schema))

  # Session is deliberately opaque to consumers but shared across Fluffy's
  # backend modules. Dialyzer has no friend-module concept, so these three
  # session-preserving public wrappers otherwise report only that internal
  # implementation access as an opaque-contract violation.
  @dialyzer {:nowarn_function, trace: 2}
  @dialyzer {:nowarn_function, screenshot: 3}
  @dialyzer {:nowarn_function, evaluate: 3}

  @doc """
  Starts a Playwright trace for this session's BrowserContext.

  The trace includes every page in the session and is saved when the test's
  lifecycle scope shuts down. Because an explicit trace is primarily a local
  debugging request, its viewer opens by default; pass `open: false` in CI. A
  session may start one trace.

  ## Options

  #{NimbleOptions.docs(@trace_schema)}
  """
  @spec trace(Session.t(), [trace_option()]) :: Session.t()
  def trace(session, options \\ []) when is_list(options) do
    ensure_playwright_backend!(session, :tracing)
    options = NimbleOptions.validate!(options, @trace_schema)
    context = Session.context(session)

    if context.trace do
      raise ArgumentError, "this Playwright session is already tracing"
    end

    trace = Trace.start(context, options)

    :ok =
      Fluffy.TestScope.register_trace(
        context.resource_scope,
        context.resource_id,
        trace
      )

    Session.put_context(session, Map.put(context, :trace, Trace.public_state(trace)))
  end

  @doc """
  Saves a PNG screenshot of the active page and returns the session.

  ## Options

  #{NimbleOptions.docs(@screenshot_schema)}
  """
  @spec screenshot(Session.t(), Path.t(), [screenshot_option()]) :: Session.t()
  def screenshot(session, path, options \\ []) when is_binary(path) and is_list(options) do
    ensure_playwright_backend!(session, :screenshot)
    options = NimbleOptions.validate!(options, @screenshot_schema)
    context = Session.context(session)
    {timeout, options} = Keyword.pop(options, :timeout, context.timeout)

    screenshot_options = options ++ [connection: context.connection, timeout: timeout]

    case Screenshot.write(Session.page_state(session).page_id, path, screenshot_options) do
      :ok -> session
      {:error, error} -> raise "Could not save Playwright screenshot: #{inspect(error)}"
    end
  end

  @doc """
  Evaluates JavaScript in the active Playwright page and returns the value.

  This mirrors Playwright's page/frame evaluation semantics: promises are
  awaited by Playwright, serializable JavaScript values are returned to Elixir,
  and JavaScript or protocol failures raise.

  `evaluate/3` is a browser-only value query, so it returns the evaluated value
  rather than the Fluffy session. Use Elixir's `then/2` when a pipeline needs
  the value and then should continue with the session:

      session
      |> then(fn session ->
        title = Fluffy.Playwright.evaluate(session, "document.title")
        assert title == "Settings"
        session
      end)
      |> Fluffy.click(Fluffy.Locator.by_role(:button, name: "Continue"))

  For function-style expressions, pass `is_function: true` and `arg:`:

      Fluffy.Playwright.evaluate(session, "selector => document.querySelector(selector).textContent",
        is_function: true,
        arg: "#status"
      )

  Do not use this for JavaScript that owns a navigation, opens a page, starts a
  download, or installs a durable listener. Use the corresponding
  listener-before-action `Fluffy.wait_for/3` event API so lifecycle and
  cleanup remain owned by Fluffy. Reserve `Fluffy.unwrap/2` for uncommon
  page-local operations that have no first-class API.

  ## Options

  #{NimbleOptions.docs(Fluffy.Options.evaluate_schema())}
  """
  @spec evaluate(Session.t(), String.t(), [evaluate_option()]) :: term()
  def evaluate(session, expression, options \\ []) when is_binary(expression) and is_list(options) do
    options = Fluffy.Options.validate_evaluate!(options)
    ensure_playwright!(session)
    context = Session.context(session)

    timeout = max(Keyword.get(options, :timeout) || context.timeout, 1)

    case Frame.evaluate(Session.page_state(session).frame_id,
           expression: expression,
           is_function: options[:is_function],
           arg: options[:arg],
           connection: context.connection,
           timeout: timeout
         ) do
      {:ok, value} ->
        value

      {:error, error} ->
        raise "Playwright evaluate failed: #{inspect(error)}"
    end
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

  defp ensure_playwright_backend!(session, capability) do
    if Session.backend(session) != PlaywrightBackend do
      raise CapabilityError,
        capability: capability,
        driver: Session.current_driver(session),
        detail: "#{inspect(capability)} requires a Playwright session"
    end
  end
end
