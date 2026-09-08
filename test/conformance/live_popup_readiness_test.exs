defmodule Fluffy.Conformance.LivePopupReadinessTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Expect

  @tag driver: :playwright
  test "waits for a captured LiveView popup before it becomes active" do
    topic = "popup-ready-#{System.unique_integer([:positive])}"
    message = "connected before switch"

    session =
      :playwright
      |> start_session(
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Fluffy.TestWeb.Endpoint
      )
      |> visit("/live/chamber-map?topic=#{topic}")
      |> wait_for(Event.popup(:ready), &click(&1, by_role(:link, name: "Open ready popup")))

    :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, message})

    session
    |> switch_page(:ready)
    |> expect(Expect.visible(by_text("Broadcast: #{message}", exact: true)))
  end
end
