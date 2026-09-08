defmodule Fluffy.Conformance.StaticVisitTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "visits the static smoke page with #{driver}", %{driver: driver} do
      session =
        start_session(driver,
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Fluffy.TestWeb.Endpoint
        )

      session
      |> visit("/chamber")
      |> expect(visible(by_text("The guardian sleeps")))
    end
  end
end
