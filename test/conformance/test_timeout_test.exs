defmodule Fluffy.Conformance.TestTimeoutTest do
  # An operation that would outlast the test, by the suite's action timeout (15 s) or by
  # `timeout: :infinity`, fails at the test's timeout. `Fluffy.TestTimeoutTest` covers the
  # backstop's bounds without waiting.
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  @moduletag timeout: 2_000
  @missing by_role(:button, name: "Missing")

  setup {Fluffy.Case, :put_test_timeout}
  setup do: %{started: System.monotonic_time(:millisecond)}

  # Static checks once, so only LiveView waits.
  @tag driver: :live
  test "an action that outlasts the test fails at the test timeout with live", %{started: started} do
    session = missing_session()
    error = assert_raise(Fluffy.OperationError, fn -> click(session, @missing) end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert error.message =~ ~s|name: "Missing"|
    assert_at_test_timeout(started)
  end

  @tag driver: :live
  test "an expectation with timeout: :infinity fails at the test timeout with live", %{started: started} do
    session = missing_session()
    error = assert_raise(ExUnit.AssertionError, fn -> expect(session, to_be_visible(@missing), timeout: :infinity) end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert_at_test_timeout(started)
  end

  # LiveViewTest runs LiveViews only from the test process: the Task waits on a static page.
  @tag driver: :static
  test "a session a Task of the test starts gets the test timeout", %{started: started} do
    error =
      fn ->
        session =
          :phoenix
          |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
          |> visit("/chamber")

        assert_raise(ExUnit.AssertionError, fn -> session |> wait_for(Event.download()) |> await() end)
      end
      |> Task.async()
      |> Task.await(:infinity)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert error.message =~ "no matching download event"
    assert_at_test_timeout(started)
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
    |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
    |> visit("/live/chamber-map")
  end

  # The backstop is 1900ms after Fluffy.Case's setup, ExUnit's kill 2000ms after the test's start.
  defp assert_at_test_timeout(started), do: assert((System.monotonic_time(:millisecond) - started) in 1_800..2_000)
end

defmodule Fluffy.Conformance.PlaywrightTestTimeoutTest do
  # PlaywrightEx.Test closes a Playwright session's context at the test timeout's backstop
  # (`Fluffy.TestTimeout`), with "Test timeout of ...ms exceeded.". A module of its own, so these
  # wait alongside the LiveView ones.
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  @moduletag timeout: 2_000
  @missing by_role(:button, name: "Missing")

  setup {Fluffy.Case, :put_test_timeout}
  setup do: %{started: System.monotonic_time(:millisecond)}

  @tag driver: :playwright
  test "an action that outlasts the test fails at the test timeout with playwright", %{started: started} do
    session = start_session(:playwright)
    error = assert_raise(Fluffy.OperationError, fn -> click(session, @missing) end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert error.message =~ ~s|name: "Missing"|
    assert_at_test_timeout(started)
  end

  @tag driver: :playwright
  test "an expectation with timeout: :infinity fails at the test timeout with playwright", %{started: started} do
    session = start_session(:playwright)
    error = assert_raise(ExUnit.AssertionError, fn -> expect(session, to_be_visible(@missing), timeout: :infinity) end)

    assert error.message =~ "Test timeout of 2000ms exceeded."
    assert_at_test_timeout(started)
  end

  defp assert_at_test_timeout(started), do: assert((System.monotonic_time(:millisecond) - started) in 1_800..2_000)
end

defmodule Fluffy.Conformance.NoTestTimeoutTest do
  # Without Fluffy.Case's setup, nothing bounds a Phoenix operation but ExUnit's timeout.
  use Fluffy.Support.Case, async: true

  test "a test without Fluffy.Case has no test timeout" do
    assert Fluffy.TestTimeout.fetch() == nil
    assert Fluffy.Driver.Live.Retry.deadline(:infinity) == :infinity
  end
end
