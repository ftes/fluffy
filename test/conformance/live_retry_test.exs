defmodule Fluffy.Conformance.LiveRetryTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # Firefox dispatches input for one page of the shared browser at a time, so
  # with many parallel cases an action can queue behind others for seconds.
  @action_timeout 5_000

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "waits for an asynchronous Live render with #{driver}", %{driver: driver} do
      session = live_session(driver)

      session
      |> visit("/live/async?delay=40")
      |> expect("Status: ready" |> by_text() |> to_be_visible(), timeout: 1_000)
      |> expect(:button |> by_role(name: "Appeared") |> to_have_count(1), timeout: 1_000)
    end

    @tag driver: driver
    test "waits for an actionable Live target before clicking with #{driver}", %{driver: driver} do
      session = live_session(driver)

      session
      |> visit("/live/async?delay=40")
      |> click(by_role(:button, name: "Appeared"), timeout: @action_timeout)
      |> expect("Activated" |> by_text() |> to_be_visible(), timeout: @action_timeout)
    end
  end

  test "a Live timeout reports the latest rendered text" do
    session = live_session(:phoenix)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        session
        |> visit("/live/async?delay=1000")
        |> expect("Status: impossible" |> by_text() |> to_be_visible(), timeout: 20)
      end

    assert error.message =~ "Status: impossible"
    assert error.message =~ "Status: waiting"
  end

  test "Live locator strictness is terminal rather than retried" do
    session = :phoenix |> live_session() |> visit("/live/fluffy")
    started_at = System.monotonic_time(:millisecond)

    assert_raise Fluffy.OperationError, fn ->
      click(
        session,
        by_role(:button, name: "Rouse guardian head", exact: true),
        timeout: 500
      )
    end

    assert System.monotonic_time(:millisecond) - started_at < 250
  end

  defp live_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
