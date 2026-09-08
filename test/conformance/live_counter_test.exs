defmodule Fluffy.Conformance.LiveCounterTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "lulls a head through a real LiveView counter with #{driver}", %{driver: driver} do
      session =
        start_session(driver,
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Fluffy.TestWeb.Endpoint
        )

      session
      |> visit("/live/three-heads")
      |> click(by_role(:button, name: "Play the flute"))
      |> expect(visible(by_text("Sleeping heads: 1")))
    end
  end
end
