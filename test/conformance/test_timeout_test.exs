defmodule Fluffy.Conformance.TestTimeoutTest do
  # With no action timeout, the test's timeout bounds an operation. Fluffy's config is global.
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  @moduletag timeout: 2_000
  @missing by_role(:button, name: "Missing")

  setup_all do: put_fluffy_config(action_timeout: :infinity)
  setup {Fluffy.Case, :put_test_timeout}
  setup do: %{started: System.monotonic_time(:millisecond)}

  # Static checks once, so only LiveView waits. PlaywrightEx.Test closes the context at the same
  # moment, 100ms (5%) before ExUnit's kill: about 1900ms into the test.
  for driver <- [:live, :playwright] do
    @tag driver: driver
    test "an action without a timeout fails at the test timeout with #{driver}", %{driver: driver, started: started} do
      session = missing_session(driver)
      error = assert_raise(Fluffy.OperationError, fn -> click(session, @missing) end)

      assert error.message =~ "Test timeout of 2000ms exceeded."
      assert error.message =~ ~s|name: "Missing"|
      assert_at_test_timeout(started)
    end

    @tag driver: driver
    test "an expectation with timeout: :infinity fails at the test timeout with #{driver}", %{
      driver: driver,
      started: started
    } do
      session = missing_session(driver)
      error = assert_raise(ExUnit.AssertionError, fn -> expect(session, to_be_visible(@missing), timeout: :infinity) end)

      assert error.message =~ "Test timeout of 2000ms exceeded."
      assert_at_test_timeout(started)
    end
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
    session = missing_session(:live)
    error = assert_raise(Fluffy.OperationError, fn -> click(session, @missing, timeout: 100) end)

    refute error.message =~ "Test timeout"
    assert System.monotonic_time(:millisecond) - started < 1_500
  end

  defp missing_session(:playwright), do: start_session(:playwright)

  defp missing_session(:live) do
    :phoenix
    |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
    |> visit("/live/chamber-map")
  end

  # The backstop is 1900ms after Fluffy.Case's setup, ExUnit's kill 2000ms after the test's start.
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
