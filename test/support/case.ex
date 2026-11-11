defmodule Fluffy.TestCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Fluffy.TestCase,
        only: [
          assert_action_error: 4,
          browser_context_guids: 0,
          freeze_page: 1,
          monitor_running: 1,
          playwright_engine?: 1,
          put_session_timeout: 2
        ]
    end
  end

  # A plain function, compiled before the tests, so `@tag skip:` can call it at compile time.
  # Read at call time: compile_env would record the whole :playwright config in the app and
  # fail at boot whenever it differs.
  def playwright_engine?(engine),
    do: engine == Keyword.get(Application.fetch_env!(:fluffy, :playwright), :engine, :chromium)

  # Sets the session's timeout after its setup, which runs under the default so a loaded
  # machine cannot fail it. No public API changes a live session's timeout.
  def put_session_timeout(session, timeout) do
    Fluffy.Session.put_context(session, %{Fluffy.Session.context(session) | timeout: timeout})
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

  # Every context open across the pool: a session's context may be in any of its browsers.
  def browser_context_guids do
    for %{browser: %{} = browser} <- Fluffy.BrowserRuntime.status().slots,
        browser_context <- PlaywrightEx.Browser.contexts(browser),
        do: browser_context.guid
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

  setup context do
    :ok = Fluffy.Test.setup(context, sandbox: false)
  end
end
