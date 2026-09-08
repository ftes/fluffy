defmodule Fluffy.Conformance.LiveEventNavigationReadinessTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Expect
  alias Fluffy.Page

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
        |> expect(Page.to_have_url("/live/redirect-ready?topic=#{topic}"))

      :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, message})

      expect(session, Expect.visible(by_text("Broadcast: #{message}", exact: true)))
    end

    @tag driver: driver
    test "keeps an in-place LiveView patch out of document adoption with #{driver}", %{
      driver: driver
    } do
      driver
      |> start_test_session()
      |> visit("/live/chamber-map")
      |> click(by_role(:link, name: "Reveal passage", exact: true))
      |> expect(Page.to_have_url("/live/chamber-map?step=patched"))
      |> expect(Expect.visible(by_text("Map position: patched", exact: true)))
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
