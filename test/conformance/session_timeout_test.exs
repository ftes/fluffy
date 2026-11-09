defmodule Fluffy.Conformance.SessionTimeoutTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Session

  # Well under the global Playwright timeout (15 s).
  @session_timeout 1_000
  @missing by_role(:button, name: "Missing")

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "actions and expectations default to the session timeout with #{driver}", %{driver: driver} do
      session = short_session(driver)

      for operation <- [
            fn -> click(session, @missing) end,
            fn -> expect(session, to_be_visible(@missing)) end
          ] do
        elapsed = failure_time(operation)
        assert elapsed >= @session_timeout - 100
        assert elapsed < @session_timeout + 3_000
      end
    end

    @tag driver: driver
    test "a per-call timeout overrides the session timeout with #{driver}", %{driver: driver} do
      session = short_session(driver)

      for operation <- [
            fn -> click(session, @missing, timeout: 2_000) end,
            fn -> expect(session, to_be_visible(@missing, timeout: 2_000)) end
          ] do
        assert failure_time(operation) >= 1_900
      end
    end
  end

  # No visit on Playwright: a navigation would share the budget under test on a loaded machine.
  defp short_session(:playwright), do: start_session(:playwright, timeout: @session_timeout)

  defp short_session(:phoenix) do
    session =
      :phoenix
      |> start_session(
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Fluffy.TestWeb.Endpoint,
        timeout: @session_timeout
      )
      |> visit("/live/chamber-map")

    assert Session.current_driver(session) == :live
    session
  end

  defp failure_time(operation) do
    started = System.monotonic_time(:millisecond)

    outcome =
      try do
        operation.()
      rescue
        error in [ExUnit.AssertionError, Fluffy.OperationError, Fluffy.ActionabilityError] -> error
      end

    assert is_exception(outcome)
    System.monotonic_time(:millisecond) - started
  end
end
