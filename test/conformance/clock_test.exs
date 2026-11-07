defmodule Fluffy.Conformance.ClockTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.TestWeb.Endpoint

  @noon ~U[2024-02-02 12:00:00Z]
  @later DateTime.shift(@noon, minute: 1)

  @dates """
  <button onclick="this.nextElementSibling.textContent = new Date().toISOString()">Now</button><output></output>
  <button onclick="this.nextElementSibling.textContent = new Date().getUTCFullYear()">Year</button><output></output>
  """

  # The timer blocks the page's main thread once the clock fires it.
  @freeze ~s|<button onclick="setTimeout(() => { while (true) {} }, 100)">Freeze</button>|

  describe "Playwright" do
    @describetag driver: :playwright

    test "set_fixed_time and set_system_time set the page's Date" do
      :playwright
      |> session_for_html(@dates, base_url: Fluffy.TestServer.base_url())
      |> set_fixed_time(@noon)
      |> click(by_role(:button, name: "Now"))
      |> expect(to_be_visible(by_text("2024-02-02T12:00:00.000Z")))
      |> set_system_time(~U[2030-06-01 00:00:00Z])
      |> click(by_role(:button, name: "Year"))
      |> expect(to_be_visible(by_text("2030")))
    end

    test "an installed clock runs the app's timers and navigation" do
      session()
      |> install_clock(time: @noon)
      |> visit("/live/clock")
      |> fill(by_label("Spell"), "lumos")
      |> expect(to_be_visible(by_text("Cast: lumos")))
      |> click(by_role(:button, name: "Fade"))
      |> expect(to_be_visible(by_text("Rings: 1")))
      |> click(by_role(:link, name: "Attic"))
      |> expect(page_to_have_url(~r/room=attic$/))
      |> click(by_role(:link, name: "Three heads"))
      |> click(by_role(:button, name: "Play the flute"))
      |> expect(to_be_visible(by_text("Sleeping heads: 1")))
    end

    test "phx-debounce fires on a paused clock only once the clock runs" do
      session =
        session()
        |> install_clock(time: @noon)
        |> visit("/live/clock")
        |> pause_clock_at(@later)
        |> fill(by_label("Spell"), "lumos")

      # Longer than the 500 ms debounce in real time.
      assert_raise ExUnit.AssertionError, ~r/Cast: lumos/, fn ->
        expect(session, to_be_visible(by_text("Cast: lumos"), timeout: 800))
      end

      session
      |> run_clock_for(500)
      |> expect(to_be_visible(by_text("Cast: lumos")))
    end

    test "actions and navigation work on a paused clock" do
      session()
      |> install_clock(time: @noon)
      |> visit("/live/clock")
      |> pause_clock_at(@later)
      |> click(by_role(:button, name: "Ring"))
      |> expect(to_be_visible(by_text("Rings: 1")))
      |> click(by_role(:link, name: "Attic"))
      |> expect(to_be_visible(by_text("Room: attic")))
      |> click(by_role(:link, name: "Three heads"))
      |> click(by_role(:button, name: "Play the flute"))
      |> expect(to_be_visible(by_text("Sleeping heads: 1")))
      |> visit("/live/clock")
      |> click(by_role(:link, name: "Chamber"))
      |> expect(to_be_visible(by_text("The guardian sleeps")))
      # A new document keeps the clock paused.
      |> visit("/live/clock")
      |> fill(by_label("Spell"), "nox")
      |> resume_clock()
      |> expect(to_be_visible(by_text("Cast: nox")))
    end

    test "a paused clock freezes the app's timers, not Fluffy's actions" do
      session =
        session()
        |> install_clock(time: @noon)
        |> visit("/live/clock")
        |> pause_clock_at(@later)
        |> click(by_role(:button, name: "Fade"))

      # The transition defers LiveView's patch until its timer fires.
      assert_raise ExUnit.AssertionError, ~r/Rings: 1/, fn ->
        expect(session, to_be_visible(by_text("Rings: 1"), timeout: 500))
      end

      session
      |> fast_forward_clock(500)
      |> expect(to_be_visible(by_text("Rings: 1")))
    end

    test "a clock call that a blocked page cannot finish fails after its timeout" do
      session =
        :playwright
        |> session_for_html(@freeze, base_url: Fluffy.TestServer.base_url())
        |> install_clock(time: @noon)
        |> pause_clock_at(@later)
        |> click(by_role(:button, name: "Freeze"))

      started = System.monotonic_time(:millisecond)

      assert_raise RuntimeError, ~r/run_clock_for did not finish within 500ms/, fn ->
        run_clock_for(session, 200, timeout: 500)
      end

      assert System.monotonic_time(:millisecond) - started < 5_000
    end
  end

  @tag driver: :live
  test "the clock requires Playwright" do
    session = :phoenix |> start_session(endpoint: Endpoint) |> visit("/live/clock")

    for call <- [
          &install_clock(&1, time: @noon),
          &pause_clock_at(&1, @noon),
          &run_clock_for(&1, 500),
          &fast_forward_clock(&1, 500),
          &resume_clock/1,
          &set_fixed_time(&1, @noon),
          &set_system_time(&1, @noon)
        ] do
      assert_raise Fluffy.CapabilityError, ~r/:clock requires a Playwright session/, fn -> call.(session) end
    end
  end

  defp session, do: start_session(:playwright, base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
end
