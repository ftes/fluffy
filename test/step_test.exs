defmodule Fluffy.StepTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright, only: [step: 3, step: 4]

  test "returns the callback's updated session" do
    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit("/live/three-heads")
      |> step("Lull one of Fluffy's heads", fn session ->
        click(session, by_role(:button, name: "Play the flute"))
      end)
      |> step("Lull another", &click(&1, by_role(:button, name: "Play the flute")), box: true, timeout: 5_000)

    expect(session, "Sleeping heads: 2" |> by_text() |> to_be_visible())
  end

  test "requires the callback to return a session and rejects unknown options" do
    session = start_session(:playwright, base_url: Fluffy.TestServer.base_url())

    assert_raise ArgumentError, ~r/must return a Fluffy.Session, got: :ok/, fn ->
      step(session, "Feed Fluffy", fn _session -> :ok end)
    end

    assert_raise ArgumentError, ~r/unknown keys \[:location\]/, fn ->
      step(session, "Feed Fluffy", & &1, location: %{})
    end
  end

  test "raises a capability error on Phoenix" do
    session = start_session(:phoenix, endpoint: Fluffy.TestWeb.Endpoint)

    assert_raise Fluffy.CapabilityError, ~r/:steps requires a Playwright session/, fn ->
      step(session, "Feed Fluffy", & &1)
    end
  end
end
