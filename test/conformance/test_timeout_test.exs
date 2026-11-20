defmodule Fluffy.Conformance.TestTimeoutTest do
  # An operation that would outlast the test, by the suite's action timeout (15 s) on a
  # browser or by `timeout: :infinity`, never capped on a Phoenix session, fails at the test's
  # timeout. `Fluffy.TestTimeoutTest` covers the
  # backstop's bounds without waiting.
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event

  @moduletag timeout: 2_000
  @missing by_role(:button, name: "Missing")

  setup do: %{started: System.monotonic_time(:millisecond)}

  # Static checks once, so only LiveView waits.
  @tag driver: :live
  test "an action that outlasts the test fails at the test timeout with live" do
    session = missing_session()
    error = assert_raise(Fluffy.OperationError, fn -> click(session, @missing, timeout: :infinity) end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert error.message =~ ~s|name: "Missing"|
    assert_at_test_timeout()
  end

  @tag driver: :live
  test "an expectation with timeout: :infinity fails at the test timeout with live" do
    session = missing_session()
    error = assert_raise(ExUnit.AssertionError, fn -> expect(session, to_be_visible(@missing), timeout: :infinity) end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert_at_test_timeout()
  end

  # LiveViewTest runs LiveViews only from the test process: the Task waits on a static page.
  @tag driver: :static
  test "a session a Task of the test starts gets the test timeout" do
    error =
      fn ->
        session =
          :phoenix
          |> start_session()
          |> visit("/chamber")

        assert_raise(ExUnit.AssertionError, fn -> session |> wait_for(Event.download(), timeout: :infinity) |> await() end)
      end
      |> Task.async()
      |> Task.await(:infinity)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert error.message =~ "no matching download event"
    assert_at_test_timeout()
  end

  @tag driver: :live
  test "a shorter timeout fails as before", %{started: started} do
    session = missing_session()
    error = assert_raise(Fluffy.OperationError, fn -> click(session, @missing, timeout: 100) end)

    refute error.message =~ "Test timeout"
    assert System.monotonic_time(:millisecond) - started < 1_500
  end

  defp missing_session do
    :phoenix
    |> start_session()
    |> visit("/live/chamber-map")
  end

  # The backstop is 100ms before ExUnit's deadline, which counts from the test's first setup.
  defp assert_at_test_timeout do
    %{deadline: deadline} = Playwright.Test.info()
    assert System.monotonic_time(:millisecond) in (deadline - 100)..deadline
  end
end

defmodule Fluffy.Conformance.PlaywrightTestTimeoutTest do
  # Playwright.Test closes a Playwright session's context at the test timeout's backstop
  # (`Fluffy.TestTimeout`), with "Test timeout of ...ms exceeded.". A module of its own, so these
  # wait alongside the LiveView ones.
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event

  @moduletag timeout: 2_000
  @missing by_role(:button, name: "Missing")

  @tag driver: :playwright
  test "an action that outlasts the test fails at the test timeout with playwright" do
    session = start_session(:playwright)
    error = assert_raise(Fluffy.OperationError, fn -> click(session, @missing) end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert error.message =~ ~s|name: "Missing"|
    assert_at_test_timeout()
  end

  @tag driver: :playwright
  test "an expectation with timeout: :infinity fails at the test timeout with playwright" do
    session = start_session(:playwright)
    error = assert_raise(ExUnit.AssertionError, fn -> expect(session, to_be_visible(@missing), timeout: :infinity) end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert_at_test_timeout()
  end

  # Fluffy's own wait, as Playwright Test's `waitForEvent`, not the page close it sees then.
  @tag driver: :playwright
  test "an event wait that outlasts the test fails at the test timeout with playwright" do
    session = start_session(:playwright)
    error = assert_raise(ExUnit.AssertionError, fn -> session |> wait_for(Event.download()) |> await() end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert error.message =~ "no matching download event"
    assert_at_test_timeout()
  end

  # The backstop is 100ms before ExUnit's deadline, which counts from the test's first setup.
  defp assert_at_test_timeout do
    %{deadline: deadline} = Playwright.Test.info()
    assert System.monotonic_time(:millisecond) in (deadline - 100)..deadline
  end
end

defmodule Fluffy.Conformance.SlowSetupTestTimeoutTest do
  # ExUnit's timeout counts from the test's first setup, and so does the backstop: after a slow
  # setup before the test's registration, such as a ConnCase's, a hanging LiveView action still
  # fails with Fluffy's error before ExUnit kills the test.
  use ExUnit.Case, async: true
  use Playwright.Test

  import Fluffy
  import Fluffy.Locator

  @moduletag timeout: 2_000

  # Counted from here, the backstop would come 500ms after ExUnit's kill.
  setup do
    Process.sleep(500)
  end

  @tag driver: :live
  test "a slow first setup leaves the backstop before ExUnit's timeout with live" do
    session =
      :phoenix
      |> start_session()
      |> visit("/live/chamber-map")

    error =
      assert_raise(Fluffy.OperationError, fn -> click(session, by_role(:button, name: "Missing"), timeout: :infinity) end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    %{deadline: deadline} = Playwright.Test.info()
    assert System.monotonic_time(:millisecond) in (deadline - 100)..deadline
  end
end

defmodule Fluffy.Conformance.NoTestTimeoutTest do
  use ExUnit.Case, async: true

  test "a test outside Playwright.Test has no test timeout" do
    assert Fluffy.TestTimeout.fetch() == nil
    assert Fluffy.Driver.Live.Retry.deadline(:infinity) == :infinity
  end
end
