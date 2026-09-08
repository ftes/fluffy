defmodule Fluffy.Conformance.LiveSessionTransitionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Page
  alias Fluffy.TestWeb.Endpoint

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "preserves session identity across Static and Live pages with #{driver}", %{
      driver: driver
    } do
      session =
        start_session(driver,
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Endpoint
        )

      session
      |> visit("/session/start?identity=flute-keeper")
      |> expect(Page.to_have_url("/live/session"))
      |> expect(visible(by_text("Live identity: flute-keeper")))
      |> click(by_role(:link, name: "Show static identity", exact: true))
      |> expect(Page.to_have_url("/session/show"))
      |> expect(visible(by_text("Static identity: flute-keeper")))
    end

    @tag driver: driver
    test "reclassifies each document across Static, Live, and Static with #{driver}", %{
      driver: driver
    } do
      session =
        start_session(driver,
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Endpoint
        )

      session
      |> visit("/actions/live")
      |> expect(visible(by_text("Enter the live chamber")))
      |> click(by_role(:link, name: "Enter the live chamber", exact: true))
      |> expect(Page.to_have_url("/live/chamber-map"))
      |> expect(visible(by_text("Map position: initial")))
      |> click(by_role(:link, name: "Sleeping chamber", exact: true))
      |> expect(Page.to_have_url("/chamber"))
      |> expect(visible(by_text("The guardian sleeps")))
    end

    @tag driver: driver
    test "preserves Live redirect flash with #{driver}", %{driver: driver} do
      session =
        start_session(driver,
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Endpoint
        )

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:button, name: "Open secret passage", exact: true))
      |> expect(Page.to_have_url("/live/secret-chamber"))
      |> expect(visible(by_text("The secret passage opened")))
    end
  end
end
