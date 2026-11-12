defmodule Fluffy.Conformance.SessionTimeoutTest do
  use Fluffy.Support.Case, async: true

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

  # The session timeout is the context's default navigation timeout too, which PlaywrightEx.Test
  # sets to none.
  @tag driver: :playwright
  test "native navigations default to the session timeout" do
    session = start_session(:playwright, timeout: @session_timeout)
    started = System.monotonic_time(:millisecond)

    assert {:error, %PlaywrightEx.TimeoutError{}} =
             unwrap_and_return(session, &PlaywrightEx.Page.wait_for_url(&1, "**/never"))

    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed >= @session_timeout - 100
    assert elapsed < @session_timeout + 3_000
  end

  @tag driver: :playwright
  test "a session timeout too short for Playwright's bookkeeping limits only the operation" do
    session = start_session(:playwright, timeout: 1)

    assert_raise Fluffy.OperationError, ~r/wait_for.*Timeout 1ms/s, fn ->
      wait_for(session, by_css("#missing"), [])
    end
  end

  @tag driver: :playwright
  test "Playwright navigation bookkeeping does not depend on a short session timeout" do
    :playwright
    |> session_for_html(~s|<a href="/chamber">Chamber</a>|)
    |> put_session_timeout(1)
    |> click(by_role(:link, name: "Chamber"), timeout: 5_000)
    |> reload(timeout: 5_000)
    |> Fluffy.Playwright.go_back(timeout: 5_000)
    |> expect(page_to_have_url("/harness"), timeout: 5_000)
  end

  # No visit on Playwright: a navigation would share the budget under test on a loaded machine.
  defp short_session(:playwright), do: start_session(:playwright, timeout: @session_timeout)

  defp short_session(:phoenix) do
    session =
      :phoenix
      |> start_session(
        base_url: Fluffy.Support.Server.base_url(),
        endpoint: Fluffy.Support.Web.Endpoint,
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
