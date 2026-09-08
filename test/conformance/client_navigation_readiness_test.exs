defmodule Fluffy.Conformance.ClientNavigationReadinessTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Expect
  alias Fluffy.Page
  alias Fluffy.TestWeb.Endpoint

  for {operation, button} <- [assign: "Assign ready", replace: "Replace ready"] do
    @tag driver: :playwright
    test "adopts a LiveView reached by client-side #{operation}" do
      topic = "client-#{unquote(operation)}-#{System.unique_integer([:positive])}"
      message = "#{unquote(operation)} connected"
      destination = "/live/redirect-ready?topic=#{topic}"

      session =
        :playwright
        |> start_session(
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Endpoint
        )
        |> visit("/actions/client-navigation?topic=#{topic}")
        |> click(by_role(:button, name: unquote(button)))
        |> expect(Page.to_have_url(destination))

      :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, message})

      expect(session, Expect.visible(by_text("Broadcast: #{message}", exact: true)))
    end
  end

  @tag driver: :playwright
  test "adopts a document-level client-side history traversal" do
    :playwright
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
    |> visit("/actions/history-source")
    |> click(by_role(:button, name: "Open secret passage"))
    |> expect(Page.to_have_url("/actions/history-target"))
    |> click(by_role(:button, name: "Back to chamber entrance"))
    |> expect(Page.to_have_url("/actions/history-source"))
    |> expect(Expect.visible(by_role(:button, name: "Open secret passage")))
  end

  @tag driver: :playwright
  test "keeps a client-side history state change out of document adoption" do
    :playwright
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint,
      timeout: 500
    )
    |> visit("/actions/history-push-state")
    |> click(by_role(:button, name: "Reveal secret passage"))
    |> expect(Page.to_have_url("/actions/history-push-state?step=pushed"))
  end
end
