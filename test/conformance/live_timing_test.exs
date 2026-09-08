defmodule Fluffy.Conformance.LiveTimingTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Locator

  describe "Phoenix eager change synchronization" do
    for {label, field} <- [
          {"Bare debounce", "bare"},
          {"Numeric debounce", "numeric"},
          {"Throttled", "throttled"},
          {"Invalid throttle", "invalid"}
        ] do
      test "ignores timing semantics for #{label}" do
        probe = probe("phoenix-eager")

        :phoenix
        |> start_test_session()
        |> visit("/live/timing?probe=#{probe}")
        |> fill(by_label(unquote(label)), "current value")

        assert_receive {:timing_change, ^probe, %{unquote(field) => "current value"}}, 0
        refute_receive {:timing_change, ^probe, _payload}, 50
      end
    end

    test "dispatches each mutation instead of coalescing them" do
      probe = probe("phoenix-not-coalesced")

      :phoenix
      |> start_test_session()
      |> visit("/live/timing?probe=#{probe}")
      |> fill(by_label("Bare debounce"), "first value")
      |> fill(by_label("Bare debounce"), "final value")

      assert_receive {:timing_change, ^probe, %{"bare" => "first value"}}, 0
      assert_receive {:timing_change, ^probe, %{"bare" => "final value"}}, 0
      refute_receive {:timing_change, ^probe, _payload}, 50
    end

    test "blur does not dispatch a second change" do
      probe = probe("phoenix-blur")

      :phoenix
      |> start_test_session()
      |> visit("/live/timing?probe=#{probe}")
      |> fill(by_label("Numeric debounce"), "already sent")
      |> blur(by_label("Numeric debounce"))

      assert_receive {:timing_change, ^probe, %{"numeric" => "already sent"}}, 0
      refute_receive {:timing_change, ^probe, _payload}, 50
    end

    test "submit follows the already synchronized change" do
      probe = probe("phoenix-submit")

      :phoenix
      |> start_test_session()
      |> visit("/live/timing?probe=#{probe}")
      |> fill(by_label("Bare debounce"), "submitted value")
      |> submit(by_css("#timing-form"))

      assert_receive {:timing_change, ^probe, %{"bare" => "submitted value"}}, 0
      assert_receive {:timing_submit, ^probe, %{"bare" => "submitted value"}}, 0
      refute_receive {:timing_change, ^probe, _payload}, 50
    end
  end

  describe "Playwright browser timing oracle" do
    @tag driver: :playwright
    test "bare debounce is trailing and does not need another Fluffy call" do
      probe = probe("browser-bare")

      :playwright
      |> start_test_session()
      |> visit("/live/timing?probe=#{probe}")
      |> fill(by_label("Bare debounce"), "trailing value")

      refute_receive {:timing_change, ^probe, _payload}, 50

      assert_receive {:timing_change, ^probe, %{"bare" => "trailing value"}}, 1_000
      refute_receive {:timing_change, ^probe, _payload}, 50
    end

    @tag driver: :playwright
    test "later debounce input coalesces to the final form state" do
      probe = probe("browser-coalesced")

      :playwright
      |> start_test_session()
      |> visit("/live/timing?probe=#{probe}")
      |> fill(by_label("Bare debounce"), "first value")
      |> fill(by_label("Bare debounce"), "final value")

      refute_receive {:timing_change, ^probe, _payload}, 50
      assert_receive {:timing_change, ^probe, %{"bare" => "final value"}}, 1_000
      refute_receive {:timing_change, ^probe, _payload}, 350
    end

    @tag driver: :playwright
    test "numeric debounce flushes once when focus moves" do
      probe = probe("browser-blur")

      session =
        :playwright
        |> start_test_session()
        |> visit("/live/timing?probe=#{probe}")
        |> fill(by_label("Numeric debounce"), "flush on focus")

      refute_receive {:timing_change, ^probe, _payload}, 10
      focus(session, by_label("Bare debounce"))

      assert_receive {:timing_change, ^probe, %{"numeric" => "flush on focus"}}, 1_000
      refute_receive {:timing_change, ^probe, _payload}, 350
    end

    @tag driver: :playwright
    test "throttle is leading-only and re-enters after expiry" do
      probe = probe("browser-throttle")

      session =
        :playwright
        |> start_test_session()
        |> visit("/live/timing?probe=#{probe}")
        |> fill(by_label("Throttled"), "leading value")

      assert_receive {:timing_change, ^probe, %{"throttled" => "leading value"}}, 1_000

      session = fill(session, by_label("Throttled"), "suppressed value")
      refute_receive {:timing_change, ^probe, _payload}, 1_050

      fill(session, by_label("Throttled"), "re-entry value")
      assert_receive {:timing_change, ^probe, %{"throttled" => "re-entry value"}}, 1_000
    end

    @tag driver: :playwright
    test "clicked submit flushes numeric debounce before submit without a later change" do
      probe = probe("browser-submit")

      :playwright
      |> start_test_session()
      |> visit("/live/timing?probe=#{probe}")
      |> fill(by_label("Numeric debounce"), "submit current value")
      |> click(by_role(:button, name: "Save timing"))

      assert_receive {:timing_change, ^probe, %{"numeric" => "submit current value"}}, 1_000
      assert_receive {:timing_submit, ^probe, %{"numeric" => "submit current value"}}, 1_000
      refute_receive {:timing_change, ^probe, _payload}, 350
    end
  end

  defp probe(prefix) do
    name = "#{prefix}-#{System.unique_integer([:positive])}"
    {:ok, _} = Registry.register(Fluffy.TestTimingProbe, name, nil)
    name
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
