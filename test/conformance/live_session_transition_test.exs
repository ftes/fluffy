defmodule Fluffy.Conformance.LiveSessionTransitionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

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
      |> expect(Fluffy.Expect.page_to_have_url("/live/session"))
      |> expect("Live identity: flute-keeper" |> by_text() |> to_be_visible())
      |> click(by_role(:link, name: "Show static identity", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/session/show"))
      |> expect("Static identity: flute-keeper" |> by_text() |> to_be_visible())
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
      |> expect("Enter the live chamber" |> by_text() |> to_be_visible())
      |> click(by_role(:link, name: "Enter the live chamber", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/live/chamber-map"))
      |> expect("Map position: initial" |> by_text() |> to_be_visible())
      |> click(by_role(:link, name: "Sleeping chamber", exact: true))
      |> expect(Fluffy.Expect.page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
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
      |> expect(Fluffy.Expect.page_to_have_url("/live/secret-chamber"))
      |> expect("The secret passage opened" |> by_text() |> to_be_visible())
    end
  end
end
