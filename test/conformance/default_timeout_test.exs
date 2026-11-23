defmodule Fluffy.Conformance.DefaultTimeoutTest do
  # The defaults of an operation without `timeout:` (`Fluffy.Timeouts`). A browser session's are
  # Playwright Test's: the test's action and navigation timeouts (here the module's,
  # `Playwright.Test.use/1`) and the config's expect timeout. A Phoenix session's is
  # `config :fluffy, phoenix_backend_timeout:`. Both of those are global config. A call's own
  # `timeout:` is `Fluffy.Conformance.TimeoutOptionTest`'s.
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Session
  alias Fluffy.Support.HTTPFixtures

  # Short, as the tests wait them out, and apart, so the time a failure took tells which one
  # applied.
  @expect_timeout 200
  @phoenix_timeout 400
  @action_timeout 600
  @navigation_timeout 300
  # A failure comes at its timeout or later, give or take a timer's precision.
  @early 50
  @missing by_role(:button, name: "Missing")
  @appeared by_role(:button, name: "Appeared")

  # `visit` takes no `timeout:`: the visits of these tests get a long default, and the
  # navigation tests set theirs.
  @moduletag Playwright.Test.use(action_timeout: @action_timeout, navigation_timeout: 5_000)

  setup_all do
    put_playwright_config(:test, expect: [timeout: @expect_timeout])
    put_fluffy_config(phoenix_backend_timeout: @phoenix_timeout)
  end

  @tag driver: :playwright
  test "a browser session's operations default to the test's timeouts" do
    session = missing_session(:playwright)

    {elapsed, error} = failure(fn -> expect(session, to_be_visible(@missing)) end)
    assert elapsed in (@expect_timeout - @early)..(@phoenix_timeout - 1)
    assert error.message =~ "Timeout: #{@expect_timeout}ms"

    {elapsed, error} = failure(fn -> click(session, @missing) end)
    assert elapsed >= @action_timeout - @early
    assert error.message =~ "Timeout #{@action_timeout}ms exceeded."

    # As Playwright's `waitForEvent`, the action timeout.
    {elapsed, _error} = failure(fn -> session |> wait_for(Event.download()) |> await() end)
    assert elapsed >= @action_timeout - @early
  end

  @tag driver: :phoenix
  test "a Phoenix session's operations default to phoenix_backend_timeout" do
    session = missing_session(:phoenix)

    for operation <- [
          fn -> expect(session, to_be_visible(@missing)) end,
          fn -> click(session, @missing) end,
          fn -> session |> wait_for(Event.download()) |> await() end
        ] do
      {elapsed, _error} = failure(operation)
      assert elapsed in (@phoenix_timeout - @early)..(@action_timeout - 1)
    end
  end

  # Playwright's timeouts are browser sessions' only.
  for driver <- Drivers.backends() do
    @tag driver: driver
    @tag Playwright.Test.use(action_timeout: 300)
    test "a tag's action_timeout is a browser session's, not a Phoenix one's, with #{driver}", %{driver: driver} do
      session = missing_session(driver)

      {elapsed, error} = failure(fn -> click(session, @missing) end)

      if driver == :playwright do
        assert elapsed in (300 - @early)..(@phoenix_timeout - 1)
        assert error.message =~ "Timeout 300ms exceeded."
      else
        assert elapsed in (@phoenix_timeout - @early)..(@action_timeout - 1)
      end
    end

    # A call's own is over every default. The button renders after them.
    @tag driver: driver
    test "timeout: :infinity waits past the defaults with #{driver}", %{driver: driver} do
      driver
      |> start_session()
      |> visit("/live/async?delay=#{@action_timeout + 100}")
      |> expect(to_be_visible(@appeared), timeout: :infinity)
      |> click(@appeared, timeout: :infinity)
      |> expect("Activated" |> by_text() |> to_be_visible(timeout: :infinity))
    end
  end

  # Playwright's `0` means no limit, not check once: the button renders after the other
  # timeouts.
  @tag driver: :playwright
  @tag Playwright.Test.use(action_timeout: 0)
  test "Playwright's timeouts of 0 mean no limit" do
    put_playwright_config(:test, expect: [timeout: 0])

    :playwright
    |> start_session()
    |> visit("/live/async?delay=#{@action_timeout + 100}")
    |> expect(to_be_visible(@appeared))
    |> click(@appeared)
    |> expect("Activated" |> by_text() |> to_be_visible())
  end

  # The button renders after the default.
  @tag driver: :phoenix
  test "phoenix_backend_timeout: :infinity waits without a limit" do
    put_fluffy_config(phoenix_backend_timeout: :infinity)

    :phoenix
    |> start_session()
    |> visit("/live/async?delay=#{@phoenix_timeout + 100}")
    |> click(@appeared)
    |> expect("Activated" |> by_text() |> to_be_visible())
  end

  # As a call's `timeout: 0`.
  @tag driver: :phoenix
  test "phoenix_backend_timeout: 0 checks a Phoenix session's operations once" do
    put_fluffy_config(phoenix_backend_timeout: 0)

    session =
      :phoenix
      |> start_session()
      |> visit("/live/async?delay=1000")

    {elapsed, _error} = failure(fn -> expect(session, to_be_visible(@appeared)) end)
    assert elapsed < @expect_timeout
    {elapsed, _error} = failure(fn -> click(session, @appeared) end)
    assert elapsed < @expect_timeout
  end

  # As in Playwright, a route that never answers leaves the navigation to its timeout.
  @tag driver: :playwright
  @tag Playwright.Test.use(navigation_timeout: @navigation_timeout)
  test "navigations default to the test's navigation_timeout" do
    session = start_session(:playwright)
    fixture = HTTPFixtures.register(fn _request -> %{body: "<h1>Never</h1>"} end)
    Fluffy.Playwright.route(session, "**/never", fn _route -> :ok end)

    {elapsed, error} = failure(fn -> visit(session, HTTPFixtures.path(fixture, "/never")) end)
    assert %Playwright.TimeoutError{message: message} = error.cause
    assert message =~ "Timeout #{@navigation_timeout}ms exceeded."
    assert elapsed >= @navigation_timeout - @early
  end

  # Playwright.Test sets them on the test's contexts: a native call gets them too.
  @tag driver: :playwright
  @tag Playwright.Test.use(navigation_timeout: @navigation_timeout)
  test "native calls default to the test's action and navigation timeouts" do
    session = start_session(:playwright)

    {elapsed, error} =
      native_failure(fn -> Fluffy.Playwright.unwrap_and_return(session, @missing, &Playwright.Locator.click/1) end)

    assert error.message =~ "Timeout #{@action_timeout}ms exceeded."
    assert elapsed >= @action_timeout - @early

    {elapsed, error} =
      native_failure(fn -> Fluffy.unwrap_and_return(session, &Playwright.Page.wait_for_url(&1, "**/never")) end)

    assert error.message =~ "Timeout #{@navigation_timeout}ms exceeded."
    assert elapsed >= @navigation_timeout - @early
  end

  # No visit on Playwright: a navigation would share the budget under test on a loaded machine.
  defp missing_session(:playwright), do: start_session(:playwright)

  defp missing_session(:phoenix) do
    session =
      :phoenix
      |> start_session()
      |> visit("/live/chamber-map")

    assert Session.current_driver(session) == :live
    session
  end

  defp failure(operation), do: timed(fn -> rescue_failure(operation) end)

  defp rescue_failure(operation) do
    operation.()
  rescue
    error in [ExUnit.AssertionError, Fluffy.OperationError, Fluffy.ActionabilityError] -> error
  else
    _result -> flunk("expected the operation to fail")
  end

  defp native_failure(operation) do
    timed(fn ->
      assert {:error, %Playwright.TimeoutError{} = error} = operation.()
      error
    end)
  end

  defp timed(fun) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    {System.monotonic_time(:millisecond) - started, result}
  end
end

defmodule Fluffy.Conformance.TimeoutOptionTest do
  # A call's `timeout:` over the suite's defaults (`config/test.exs`: 15 s for actions, 5 s for
  # expectations), which these tests never wait out.
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Session

  @timeout 300
  @early 50
  @missing by_role(:button, name: "Missing")
  @appeared by_role(:button, name: "Appeared")

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "a per-call timeout overrides the default with #{driver}", %{driver: driver} do
      session = missing_session(driver)

      {elapsed, error} = failure(fn -> click(session, @missing, timeout: @timeout) end)
      assert elapsed in (@timeout - @early)..5_000
      if driver == :playwright, do: assert(error.message =~ "Timeout #{@timeout}ms exceeded.")

      {elapsed, error} = failure(fn -> expect(session, to_be_visible(@missing, timeout: @timeout)) end)
      assert elapsed in (@timeout - @early)..5_000
      if driver == :playwright, do: assert(error.message =~ "Timeout: #{@timeout}ms")
    end

    # Playwright's 0 would wait for the button.
    @tag driver: driver
    test "timeout: 0 checks an expectation once with #{driver}", %{driver: driver} do
      session =
        driver
        |> start_session()
        |> visit("/live/async?delay=1000")

      {elapsed, _error} = failure(fn -> expect(session, to_be_visible(@appeared), timeout: 0) end)
      assert elapsed < 1_000
    end
  end

  @tag driver: :live
  test "LiveView actions check once with timeout: 0" do
    session = missing_session(:phoenix)
    {elapsed, _error} = failure(fn -> click(session, @missing, timeout: 0) end)
    assert elapsed < 1_000
  end

  @tag driver: :playwright
  test "a timeout too short for Playwright's bookkeeping limits only the operation" do
    session = start_session(:playwright)

    assert_raise Fluffy.OperationError, ~r/wait_for.*Timeout 1ms/s, fn ->
      wait_for(session, by_css("#missing"), timeout: 1)
    end
  end

  @tag driver: :playwright
  test "Playwright navigation bookkeeping does not depend on a short action timeout" do
    :playwright
    |> session_for_html(~s|<a href="/chamber">Chamber</a>|)
    |> click(by_role(:link, name: "Chamber"), timeout: 500)
    |> reload(timeout: 5_000)
    |> Fluffy.Playwright.go_back(timeout: 5_000)
    |> expect(page_to_have_url("/harness"), timeout: 5_000)
  end

  # No visit on Playwright: a navigation would share the budget under test on a loaded machine.
  defp missing_session(:playwright), do: start_session(:playwright)

  defp missing_session(:phoenix) do
    session =
      :phoenix
      |> start_session()
      |> visit("/live/chamber-map")

    assert Session.current_driver(session) == :live
    session
  end

  defp failure(operation) do
    started = System.monotonic_time(:millisecond)
    error = rescue_failure(operation)
    {System.monotonic_time(:millisecond) - started, error}
  end

  defp rescue_failure(operation) do
    operation.()
  rescue
    error in [ExUnit.AssertionError, Fluffy.OperationError, Fluffy.ActionabilityError] -> error
  else
    _result -> flunk("expected the operation to fail")
  end
end
