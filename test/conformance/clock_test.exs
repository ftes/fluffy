defmodule Fluffy.Conformance.ClockTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Playwright.Clock
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  @noon ~U[2024-02-02 12:00:00Z]
  @later DateTime.shift(@noon, minute: 1)

  @dates """
  <button onclick="this.nextElementSibling.textContent = new Date().toISOString()">Now</button><output></output>
  <button onclick="this.nextElementSibling.textContent = new Date().getUTCFullYear()">Year</button><output></output>
  """

  describe "Playwright" do
    @describetag driver: :playwright

    test "set_fixed_time and set_system_time set the page's Date" do
      :playwright
      |> session_for_html(@dates, base_url: Server.base_url())
      |> Clock.set_fixed_time(@noon)
      |> click(by_role(:button, name: "Now"))
      |> expect(to_be_visible(by_text("2024-02-02T12:00:00.000Z")))
      |> Clock.set_system_time(~U[2030-06-01 00:00:00Z])
      |> click(by_role(:button, name: "Year"))
      |> expect(to_be_visible(by_text("2030")))
    end

    test "an installed clock runs the app's timers and navigation" do
      session()
      |> Clock.install(time: @noon)
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
        |> Clock.install(time: @noon)
        |> visit("/live/clock")
        |> Clock.pause_at(@later)
        |> fill(by_label("Spell"), "lumos")

      # Longer than the 500 ms debounce in real time.
      assert_raise ExUnit.AssertionError, ~r/Cast: lumos/, fn ->
        expect(session, to_be_visible(by_text("Cast: lumos"), timeout: 800))
      end

      session
      |> Clock.run_for(500)
      |> expect(to_be_visible(by_text("Cast: lumos")))
    end

    test "actions and navigation work on a paused clock" do
      session()
      |> Clock.install(time: @noon)
      |> visit("/live/clock")
      |> Clock.pause_at(@later)
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
      |> Clock.resume()
      |> expect(to_be_visible(by_text("Cast: nox")))
    end

    test "a paused clock freezes the app's timers, not Fluffy's actions" do
      session =
        session()
        |> Clock.install(time: @noon)
        |> visit("/live/clock")
        |> Clock.pause_at(@later)
        |> click(by_role(:button, name: "Fade"))

      # The transition defers LiveView's patch until its timer fires.
      assert_raise ExUnit.AssertionError, ~r/Rings: 1/, fn ->
        expect(session, to_be_visible(by_text("Rings: 1"), timeout: 500))
      end

      session
      |> Clock.fast_forward(500)
      |> expect(to_be_visible(by_text("Rings: 1")))
    end

    # As in Playwright, clock calls have no timeout.
    test "clock calls reject timeout:" do
      session = session_for_html(:playwright, @dates, base_url: Server.base_url())

      for call <- [&Clock.install(session, &1), &Clock.run_for(session, 200, &1), &Clock.resume(session, &1)] do
        assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:timeout/, fn -> call.(timeout: 500) end
      end
    end

    # The call runs in a task, which logs the crash.
    @tag :capture_log
    test "a clock call that PlaywrightEx rejects raises its exception" do
      session = session_for_html(:playwright, @dates, base_url: Server.base_url())

      assert_raise FunctionClauseError, fn -> Clock.install(session, time: :bogus) end
    end
  end

  @tag driver: :live
  test "the clock requires Playwright" do
    session = :phoenix |> start_session(endpoint: Endpoint) |> visit("/live/clock")

    for call <- [
          &Clock.install(&1, time: @noon),
          &Clock.pause_at(&1, @noon),
          &Clock.run_for(&1, 500),
          &Clock.fast_forward(&1, 500),
          &Clock.resume/1,
          &Clock.set_fixed_time(&1, @noon),
          &Clock.set_system_time(&1, @noon)
        ] do
      assert_raise Fluffy.CapabilityError, ~r/:clock requires a Playwright session/, fn -> call.(session) end
    end
  end

  defp session, do: start_session(:playwright, base_url: Server.base_url(), endpoint: Endpoint)
end
