defmodule Fluffy.Support.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      use Playwright.Test

      import Fluffy.Support.Case,
        only: [
          assert_action_error: 4,
          browser_context_guids: 1,
          freeze_page: 1,
          monitor_running: 1,
          playwright_engine?: 1,
          put_fluffy_config: 1,
          put_playwright_config: 2,
          requires: 1,
          with_html: 3
        ]

      alias Fluffy.Support.Drivers, warn: false
    end
  end

  # Runs `fun` on a session of `driver` (`Fluffy.Support.Drivers.html/0`) showing `html`.
  def with_html(driver, html, fun), do: fun.(Fluffy.session_for_html(driver, html))

  # A plain function, compiled before the tests, so `@tag skip:` can call it at compile time.
  # Read at call time, as the config can differ between runs (FLUFFY_BROWSER).
  def playwright_engine?(engine), do: engine == Playwright.Test.config().browser_name

  # `@tag requires(app: requirement)` skips the test when the loaded `app` doesn't meet
  # `requirement`, as on CI's oldest lane, which runs every dependency at its floor.
  def requires(requirements) do
    unmet =
      for {app, requirement} <- requirements,
          not Version.match?(loaded_version!(app), requirement),
          do: "#{app} #{requirement}"

    if unmet == [],
      do: [requires: requirements],
      else: [requires: requirements, skip: "requires #{Enum.join(unmet, ", ")}"]
  end

  defp loaded_version!(app) do
    case Application.spec(app, :vsn) do
      nil -> raise ArgumentError, "requires/1: #{inspect(app)} is not a loaded application"
      vsn -> to_string(vsn)
    end
  end

  # The application's sandbox owners, as a generated DataCase starts them: Fluffy only
  # passes the test's sandbox to browser sessions. `setup {Fluffy.Support.Case, :start_sandbox}`.
  def start_sandbox(context) do
    owners =
      for repo <- [Fluffy.Support.Repo, Fluffy.Support.RepoTwo] do
        owner = Sandbox.start_owner!(repo, shared: not context[:async])
        ExUnit.Callbacks.on_exit(fn -> Sandbox.stop_owner(owner) end)
        owner
      end

    [sandbox_owners: owners]
  end

  # Puts `options` in `config :fluffy`, such as the default timeouts, until the module
  # (`setup_all`) or test (`setup`) ends; `nil` unsets a key. The config is global, so only in an
  # `async: false` module. A Playwright session sets its context's timeouts when it starts.
  def put_fluffy_config(options) do
    for {key, value} <- options do
      original = Application.fetch_env(:fluffy, key)
      if value == nil, do: Application.delete_env(:fluffy, key), else: Application.put_env(:fluffy, key, value)

      ExUnit.Callbacks.on_exit(fn ->
        case original do
          {:ok, original} -> Application.put_env(:fluffy, key, original)
          :error -> Application.delete_env(:fluffy, key)
        end
      end)
    end

    :ok
  end

  # Merges `options` into `config :playwright, :test`, as
  # `put_fluffy_config/1`. Playwright.Test reads `:test` when a test registers, in its
  # `setup`, and Fluffy when a session starts: set the context timeouts in `setup_all`.
  def put_playwright_config(:test = key, options) do
    original = Application.get_env(:playwright, key)
    Application.put_env(:playwright, key, Keyword.merge(original || [], options))

    ExUnit.Callbacks.on_exit(fn ->
      if original,
        do: Application.put_env(:playwright, key, original),
        else: Application.delete_env(:playwright, key)
    end)

    :ok
  end

  # Blocks the page's main thread for good. The loop starts in a task after the
  # evaluate returns, which has no timeout, and well before the next call arrives.
  def freeze_page(session) do
    Fluffy.Playwright.evaluate(session, "setTimeout(() => { while (true) {} }, 0); true")
    Process.sleep(100)
    session
  end

  # Signals from different processes have no order, so an exit a test triggers through
  # another process can reach `pid` before the monitor, which then reports :noproc. A
  # request from this process is handled after its monitor, so that is in place on return.
  def monitor_running(pid) do
    monitor = Process.monitor(pid)
    :sys.get_state(pid)
    monitor
  end

  # The contexts open in `browser`, which a test reads from a context while it's open
  # (`Playwright.BrowserContext.browser/1`).
  def browser_context_guids(browser) do
    for browser_context <- Playwright.Browser.contexts(browser), do: browser_context.guid
  end

  def assert_action_error(session, structural_exception, structural_message, action) do
    error = ExUnit.Assertions.assert_raise(Fluffy.OperationError, action)
    ExUnit.Assertions.assert(error.driver == Fluffy.Session.current_driver(session))
    ExUnit.Assertions.assert(is_atom(error.operation) and not is_nil(error.operation))
    ExUnit.Assertions.assert(match?(%Fluffy.Locator{}, error.locator))

    if Fluffy.Session.current_driver(session) == :playwright do
      ExUnit.Assertions.assert(error.backend == :playwright)

      ExUnit.Assertions.assert(
        is_exception(error.cause) and error.cause.__struct__ |> Module.split() |> hd() == "Playwright"
      )
    else
      ExUnit.Assertions.assert(error.backend == :phoenix)
      ExUnit.Assertions.assert(error.cause.__struct__ == structural_exception)
      ExUnit.Assertions.assert(Exception.message(error.cause) =~ structural_message)
    end

    error
  end
end
