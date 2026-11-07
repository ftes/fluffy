defmodule Fluffy.Conformance.LivePopupReadinessTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.Expect
  alias Fluffy.TestWeb.Endpoint

  @tag driver: :playwright
  test "actions on an awaited popup wait for its LiveView connection" do
    topic = "popup-ready-#{System.unique_integer([:positive])}"
    message = "connected before switch"

    session =
      :playwright
      |> start_session(
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Endpoint
      )
      |> visit("/live/chamber-map?topic=#{topic}")

    pending = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Open ready popup"))
    session = switch_page(session, await(pending))
    click(session, by_text("Redirect-ready LiveView", exact: true))

    :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, message})

    expect(session, "Broadcast: #{message}" |> by_text(exact: true) |> Expect.to_be_visible())
  end

  # Only a popup opened with a URL keeps its about:blank window for the
  # destination, and Playwright reports such a popup once that has committed.
  # A blank popup navigated later gets a new window, so a new document stamp.
  @tag driver: :playwright
  test "actions on a blank popup navigated later wait for its LiveView connection" do
    topic = "blank-popup-ready-#{System.unique_integer([:positive])}"
    message = "connected after blank"

    session =
      session_for_html(
        :playwright,
        """
        <button onclick="window.popup = window.open('', 'blank-popup')">Open blank popup</button>
        <button onclick="window.popup.location.href = '/live/redirect-ready?topic=#{topic}'">Navigate popup</button>
        """,
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Endpoint
      )

    pending = wait_for(session, Event.popup())
    click(session, by_role(:button, name: "Open blank popup"))
    popup = switch_page(session, await(pending))
    expect(popup, page_to_have_url("about:blank"))

    click(session, by_role(:button, name: "Navigate popup"))
    expect(popup, page_to_have_url(~r/redirect-ready/))
    :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, message})

    expect(popup, "Broadcast: #{message}" |> by_text(exact: true) |> Expect.to_be_visible())
  end
end
