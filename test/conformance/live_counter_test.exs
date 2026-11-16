defmodule Fluffy.Conformance.LiveCounterTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "lulls a head through a real LiveView counter with #{driver}", %{driver: driver} do
      session =
        start_session(driver,
          base_url: Fluffy.Support.Server.base_url(),
          endpoint: Fluffy.Support.Web.Endpoint
        )

      session
      |> visit("/live/three-heads")
      |> click(by_role(:button, name: "Play the flute"))
      |> expect("Sleeping heads: 1" |> by_text() |> to_be_visible())
    end
  end
end
