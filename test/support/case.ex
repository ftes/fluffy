defmodule Fluffy.Support.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      use PlaywrightEx.Test

      import Fluffy.Support.Case,
        only: [
          assert_action_error: 4,
          browser_context_guids: 1,
          freeze_page: 1,
          monitor_running: 1,
          playwright_engine?: 1,
          put_playwright_ex_config: 2
        ]

      setup {Fluffy.Support.Case, :exclusive_firefox}
    end
  end

  # A plain function, compiled before the tests, so `@tag skip:` can call it at compile time.
  # Read at call time, as the config can differ between runs (FLUFFY_BROWSER).
  def playwright_engine?(engine),
    do: engine == Keyword.get(Application.get_env(:playwright_ex, :test, []), :browser_name, :chromium)

  # Firefox dispatches input for all of a browser's pages in one queue: a browser per test,
  # taken at its first Playwright session, as Playwright Test's workers have one.
  def exclusive_firefox(_context) do
    if playwright_engine?(:firefox),
      do: Fluffy.Backend.Playwright.put_default_browser(&PlaywrightEx.Test.BrowserPool.exclusive/0),
      else: :ok
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

  # Merges `options` into `config :playwright_ex, key` (`:test` or `:expect`), such as the
  # default timeouts, until the module (`setup_all`) or test (`setup`) ends. The config is
  # global, so only in an `async: false` module. PlaywrightEx.Test reads `:test` when a test
  # registers, in its `setup`: set the context timeouts in `setup_all`.
  def put_playwright_ex_config(key, options) when key in [:test, :expect] do
    original = Application.get_env(:playwright_ex, key)
    Application.put_env(:playwright_ex, key, Keyword.merge(original || [], options))

    ExUnit.Callbacks.on_exit(fn ->
      if original,
        do: Application.put_env(:playwright_ex, key, original),
        else: Application.delete_env(:playwright_ex, key)
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
  # (`PlaywrightEx.BrowserContext.browser/1`).
  def browser_context_guids(browser) do
    for browser_context <- PlaywrightEx.Browser.contexts(browser), do: browser_context.guid
  end

  def assert_action_error(session, structural_exception, structural_message, action) do
    error = ExUnit.Assertions.assert_raise(Fluffy.OperationError, action)
    ExUnit.Assertions.assert(error.driver == Fluffy.Session.current_driver(session))
    ExUnit.Assertions.assert(is_atom(error.operation) and not is_nil(error.operation))
    ExUnit.Assertions.assert(match?(%Fluffy.Locator{}, error.locator))

    if Fluffy.Session.current_driver(session) == :playwright do
      ExUnit.Assertions.assert(error.backend == :playwright)

      ExUnit.Assertions.assert(
        is_exception(error.cause) and error.cause.__struct__ |> Module.split() |> hd() == "PlaywrightEx"
      )
    else
      ExUnit.Assertions.assert(error.backend == :phoenix)
      ExUnit.Assertions.assert(error.cause.__struct__ == structural_exception)
      ExUnit.Assertions.assert(Exception.message(error.cause) =~ structural_message)
    end

    error
  end
end
