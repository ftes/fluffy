defmodule Fluffy.Conformance.LiveEventNavigationReadinessTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Expect

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "waits for a LiveView event navigation before returning with #{driver}", %{
      driver: driver
    } do
      topic = "event-ready-#{System.unique_integer([:positive])}"
      message = "connected"

      session = start_test_session(driver)

      session =
        session
        |> visit("/live/chamber-map?topic=#{topic}")
        |> click(by_role(:button, name: "Navigate ready", exact: true))
        |> expect(Expect.page_to_have_url("/live/redirect-ready?topic=#{topic}"))

      :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, message})

      expect(session, "Broadcast: #{message}" |> by_text(exact: true) |> Expect.to_be_visible())
    end

    @tag driver: driver
    test "keeps an in-place LiveView patch out of document adoption with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/chamber-map")
      |> click(by_role(:link, name: "Reveal passage", exact: true))
      |> expect(Expect.page_to_have_url("/live/chamber-map?step=patched"))
      |> expect("Map position: patched" |> by_text(exact: true) |> Expect.to_be_visible())
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
