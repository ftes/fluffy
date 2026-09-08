defmodule Fluffy.Conformance.LiveRetryTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "waits for an asynchronous Live render with #{driver}", %{driver: driver} do
      session = live_session(driver)

      session
      |> visit("/live/async?delay=40")
      |> expect(visible(by_text("Status: ready")), timeout: 1_000)
      |> expect(count(by_role(:button, name: "Appeared"), 1), timeout: 1_000)
    end

    @tag driver: driver
    test "waits for an actionable Live target before clicking with #{driver}", %{driver: driver} do
      session = live_session(driver)

      session
      |> visit("/live/async?delay=40")
      |> click(by_role(:button, name: "Appeared"), timeout: 1_000)
      |> expect(visible(by_text("Activated")), timeout: 1_000)
    end
  end

  test "a Live timeout reports the latest rendered text" do
    session = live_session(:phoenix)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        session
        |> visit("/live/async?delay=1000")
        |> expect(visible(by_text("Status: impossible")), timeout: 20)
      end

    assert error.message =~ "Status: impossible"
    assert error.message =~ "Status: waiting"
  end

  test "Live locator strictness is terminal rather than retried" do
    session = :phoenix |> live_session() |> visit("/live/fluffy")
    started_at = System.monotonic_time(:millisecond)

    assert_raise Fluffy.StrictnessError, fn ->
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
