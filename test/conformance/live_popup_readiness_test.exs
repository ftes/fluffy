defmodule Fluffy.Conformance.LivePopupReadinessTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Expect

  @tag driver: :playwright
  test "actions on an awaited popup wait for its LiveView connection" do
    topic = "popup-ready-#{System.unique_integer([:positive])}"
    message = "connected before switch"

    session =
      :playwright
      |> start_session(
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Fluffy.TestWeb.Endpoint
      )
      |> visit("/live/chamber-map?topic=#{topic}")

    pending = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Open ready popup"))
    session = switch_page(session, await(pending))
    click(session, by_text("Redirect-ready LiveView", exact: true))

    :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, message})

    expect(session, "Broadcast: #{message}" |> by_text(exact: true) |> Expect.to_be_visible())
  end
end
