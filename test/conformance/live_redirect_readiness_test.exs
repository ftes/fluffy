defmodule Fluffy.Conformance.LiveRedirectReadinessTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Expect
  alias Fluffy.TestWeb.Endpoint

  @tag driver: :playwright
  test "controller pages await every embedded LiveView before a broadcast" do
    topic = "embedded-ready-#{System.unique_integer([:positive])}"

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/embedded-ready?topic=#{topic}")

    :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, "connected"})
    expect(session, "Broadcast: connected" |> by_text(exact: true) |> Expect.to_have_count(2))
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "waits for an HTTP-redirected LiveView before returning with #{driver}", %{
      driver: driver
    } do
      topic = "redirect-ready-#{System.unique_integer([:positive])}"
      message = "connected"

      session =
        start_session(driver,
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Endpoint
        )

      session =
        session
        |> visit("/redirect/live-ready?topic=#{topic}")
        |> expect(Expect.page_to_have_url("/live/redirect-ready?topic=#{topic}"))

      :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, message})

      expect(session, "Broadcast: #{message}" |> by_text(exact: true) |> Expect.to_be_visible())
    end
  end
end
