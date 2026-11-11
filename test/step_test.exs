defmodule Fluffy.StepTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for backend <- [:phoenix, :playwright] do
    @tag backend: backend
    test "returns the callback's updated session with #{backend}", %{backend: backend} do
      session =
        backend
        |> start_session(
          endpoint: Fluffy.TestWeb.Endpoint,
          base_url: Fluffy.TestServer.base_url()
        )
        |> visit("/live/three-heads")
        |> step("Lull one of Fluffy's heads", fn session ->
          click(session, by_role(:button, name: "Play the flute"))
        end)

      expect(session, "Sleeping heads: 1" |> by_text() |> to_be_visible())
    end
  end

  test "runs directly when a Playwright trace was not enabled" do
    session = start_session(:playwright, base_url: Fluffy.TestServer.base_url())

    assert ^session = step(session, "No trace", & &1)
  end
end
