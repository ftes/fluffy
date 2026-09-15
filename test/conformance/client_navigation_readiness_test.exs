defmodule Fluffy.Conformance.ClientNavigationReadinessTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Expect
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
        |> expect(Expect.page_to_have_url(destination))

      :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, message})

      expect(session, "Broadcast: #{message}" |> by_text(exact: true) |> Expect.to_be_visible())
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
    |> expect(Expect.page_to_have_url("/actions/history-target"))
    |> click(by_role(:button, name: "Back to chamber entrance"))
    |> expect(Expect.page_to_have_url("/actions/history-source"))
    |> expect(:button |> by_role(name: "Open secret passage") |> Expect.to_be_visible())
  end

  @tag driver: :playwright
  test "keeps a client-side history state change out of document adoption" do
    :playwright
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
    |> visit("/actions/history-push-state")
    |> click(by_role(:button, name: "Reveal secret passage"))
    |> expect(Expect.page_to_have_url("/actions/history-push-state?step=pushed"))
  end

  @tag driver: :playwright
  test "a same-URL reload adopts the new document and response" do
    counter = start_supervised!({Agent, fn -> 0 end})

    fixture =
      Fluffy.TestHTTPFixtures.register(fn _request ->
        attempt = Agent.get_and_update(counter, &{&1 + 1, &1 + 1})
        %{status: if(attempt == 1, do: 201, else: 202), body: ~s|<button onclick="location.reload()">Reload</button>|}
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit(Fluffy.TestHTTPFixtures.path(fixture))

    first = Fluffy.Session.current_page(session)
    assert Fluffy.Page.status(first) == 201
    session = click(session, by_role(:button, name: "Reload"))
    reloaded = Fluffy.Session.current_page(session)
    assert Fluffy.Page.url(reloaded) == Fluffy.Page.url(first)
    assert Fluffy.Page.status(reloaded) == 202
    assert Fluffy.Page.revision(reloaded) > Fluffy.Page.revision(first)
  end

  @tag driver: :playwright
  test "a requestless document clears the previous HTTP status" do
    fixture = Fluffy.TestHTTPFixtures.register(%{status: 201, body: ~s(<a href="about:blank">Blank</a>)})

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit(Fluffy.TestHTTPFixtures.path(fixture))
      |> click(by_role(:link, name: "Blank"))

    assert Fluffy.Page.url(Fluffy.Session.current_page(session)) == "about:blank"
    assert Fluffy.Page.status(Fluffy.Session.current_page(session)) == nil
  end
end
