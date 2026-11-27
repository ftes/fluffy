defmodule Fluffy.Conformance.LiveRetryTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # Firefox dispatches input for one page of the shared browser at a time, so
  # with many parallel cases an action can queue behind others for seconds.
  @action_timeout 5_000

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "to_be_enabled waits for an absent button to appear with #{driver}", %{driver: driver} do
      button = by_role(:button, name: "Appearing action")

      driver
      |> start_session()
      |> visit("/live/action-retries")
      |> expect(to_have_count(button, 0))
      |> click(by_role(:button, name: "Release appearing button"))
      |> expect(to_be_enabled(button), timeout: @action_timeout)
    end

    @tag driver: driver
    test "waits for an asynchronous Live render with #{driver}", %{driver: driver} do
      session = start_session(driver)

      session
      |> visit("/live/async?delay=40")
      |> expect("Status: ready" |> by_text() |> to_be_visible(), timeout: 1_000)
      |> expect(:button |> by_role(name: "Appeared") |> to_have_count(1), timeout: 1_000)
    end

    @tag driver: driver
    test "waits for an actionable Live target before clicking with #{driver}", %{driver: driver} do
      session = start_session(driver)

      session
      |> visit("/live/async?delay=40")
      |> click(by_role(:button, name: "Appeared"), timeout: @action_timeout)
      |> expect("Activated" |> by_text() |> to_be_visible(), timeout: @action_timeout)
    end
  end

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "control expectations wait for the owl to deliver their target with #{driver}", %{driver: driver} do
      recipient = by_css("#recipient")
      seal = by_css("#sealed")
      supplies = by_css("#supplies")

      for expectation <- [
            to_be_enabled(by_role(:button, name: "Read the letter")),
            to_be_editable(recipient),
            to_be_checked(seal),
            not_(to_be_checked(seal, checked: false)),
            to_have_value(recipient, "Harry"),
            to_have_values(supplies, ["wand", "robes"]),
            not_(to_have_values(supplies, []))
          ] do
        topic = "owlery-#{System.unique_integer([:positive])}"
        session = driver |> start_session() |> visit("/live/owlery?topic=#{topic}")
        {:locator, locator} = expectation.target
        expect(session, to_have_count(locator, 0))
        expect_after_owl(driver, session, expectation, topic)
        expect(session, to_have_count(locator, 1))
      end
    end
  end

  defp expect_after_owl(:playwright, session, expectation, topic) do
    {:ok, _timer} = :timer.apply_after(100, Phoenix.PubSub, :broadcast, [Fluffy.TestPubSub, topic, :owl])
    expect(session, expectation, timeout: @action_timeout)
  end

  defp expect_after_owl(:phoenix, session, expectation, topic) do
    caller = self()
    matcher = {Fluffy.Driver.Phoenix.ClientDOM.Expectation, :evaluate, 2}
    unsuccessful = expectation.negated?

    # Only the owl can mount the control. Release it after this assertion's first
    # unsuccessful evaluation, even if the test process is paused before expect.
    release =
      Task.async(fn ->
        assert_receive {:trace, ^caller, :return_from, ^matcher, {^unsuccessful, _actual}}, 5_000
        Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, :owl)
      end)

    trace = :trace.session_create(:missing_control, release.pid, [])

    try do
      1 = :trace.function(trace, matcher, [{:_, [], [{:return_trace}]}], [])
      1 = :trace.process(trace, caller, true, [:call, :arity])
      expect(session, expectation, timeout: @action_timeout)
      assert :ok = Task.await(release)
    after
      :trace.session_destroy(trace)
    end
  end

  test "a Live timeout reports the latest rendered text" do
    session = start_session(:phoenix)

    error =
      assert_raise ExUnit.AssertionError, fn ->
        session
        |> visit("/live/async?delay=20")
        |> expect("Status: impossible" |> by_text() |> to_be_visible(), timeout: 300)
      end

    assert error.message =~ "Status: impossible"
    assert error.message =~ "No element matched."
    assert error.message =~ "Status: ready"
    refute error.message =~ "Status: waiting"
  end

  test "a missing Live click suggests button names from the final render" do
    session = :phoenix |> start_session() |> visit("/live/async?delay=40")
    locator = by_role(:button, "Expelliarmus")
    error = assert_raise Fluffy.OperationError, fn -> click(session, locator, timeout: 300) end

    assert %Fluffy.StrictnessError{locator: ^locator, candidates: []} = error.cause
    assert error.message =~ ~s(Other button names in scope: "Appeared")
  end

  test "Live locator strictness is terminal rather than retried" do
    session = :phoenix |> start_session() |> visit("/live/fluffy")
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
end
