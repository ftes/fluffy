defmodule Fluffy.Conformance.DelayedControlTest do
  @moduledoc false
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  @timeout 5_000
  for driver <- Drivers.backends(),
      {matcher, selector, args} <- [
        {:to_be_editable, "#recipient", []},
        {:to_be_checked, "#sealed", []},
        {:to_have_value, "#recipient", ["Harry"]},
        {:to_have_values, "#supplies", [["wand", "robes"]]}
      ] do
    @tag driver: driver
    @tag skip:
           if(driver == :phoenix && System.get_env("FLUFFY_DELAYED_CONTROL_REPRO") != "1",
             do: "Set FLUFFY_DELAYED_CONTROL_REPRO=1 to reproduce the missing LiveView retry"
           )
    test "#{matcher} waits for the control with #{driver}", %{driver: driver} do
      topic = "owlery-#{System.unique_integer([:positive])}"
      session = driver |> start_session() |> visit("/live/owlery?topic=#{topic}")
      locator = by_css(unquote(selector))
      expectation = apply(Fluffy.Expect, unquote(matcher), [locator | unquote(args)])
      expect(session, to_have_count(locator, 0))

      release = release_during_assertion(driver, topic)
      started = System.monotonic_time(:microsecond)

      try do
        expect(session, expectation, timeout: @timeout)
      after
        elapsed = System.monotonic_time(:microsecond) - started
        release.()
        expect(session, to_have_count(locator, 1), timeout: @timeout)
        expect(session, expectation, timeout: @timeout)
        IO.puts("#{driver} #{unquote(matcher)}: first assertion #{elapsed} µs; mounted control passed")
      end
    end
  end

  defp release_during_assertion(:phoenix, topic) do
    caller = self()
    matcher = {Fluffy.Driver.Phoenix.ClientDOM.Expectation, :evaluate, 2}

    release =
      Task.async(fn ->
        receive do
          {:trace, ^caller, :exception_from, ^matcher, _exception} -> :ok
          {:trace, ^caller, :return_from, ^matcher, {false, _actual}} -> :ok
        after
          6_000 -> flunk("Missing first Phoenix matcher result")
        end

        Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, :owl)
      end)

    trace = :trace.session_create(:delayed_control, release.pid, [])
    1 = :trace.function(trace, matcher, [{:_, [], [{:exception_trace}]}], [])
    1 = :trace.process(trace, caller, true, [:call, :arity])

    fn ->
      try do
        assert :ok = Task.await(release, 7_000)
      after
        :trace.session_destroy(trace)
      end
    end
  end

  defp release_during_assertion(:playwright, topic) do
    release =
      Task.async(fn ->
        Process.sleep(300)
        Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, :owl)
      end)

    fn -> assert :ok = Task.await(release) end
  end
end
