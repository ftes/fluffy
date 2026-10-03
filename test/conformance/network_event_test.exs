defmodule Fluffy.Conformance.NetworkEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.HTTPEvent
  alias Fluffy.Playwright
  alias Fluffy.TestHTTPFixtures

  @tag driver: :playwright
  test "request and response values expose metadata without a captured-result DSL" do
    {session, fixture} = session()
    request_wait = wait_for(session, Event.request(&String.ends_with?(&1.url, "/api?source=button")))
    response_wait = wait_for(session, Event.response(&String.ends_with?(&1.url, "/api?source=button")))
    click(session, by_role(:button, name: "Save"))

    assert %HTTPEvent{kind: :request, method: "POST", status: nil, resource_type: "fetch", post_data: "payload"} =
             request = await(request_wait)

    assert request.url == TestHTTPFixtures.url(fixture, "/api?source=button")
    assert request.headers["x-fluffy"] == "network-test"
    assert request.page == current_page(session)

    assert %HTTPEvent{kind: :response, method: "POST", status: 207, status_text: "Multi-Status"} =
             response = await(response_wait)

    assert response.url == request.url
    assert response.headers["content-type"] == "application/json"
    assert response.resource_type == "fetch"
    assert response.post_data == "payload"
    assert response.page == request.page
  end

  @tag driver: :playwright
  test "page and context waits observe the same request, including child-frame requests" do
    {session, fixture} = session()
    frame_url = TestHTTPFixtures.url(fixture, "/child")
    frame_wait = wait_for(session, Event.frame_navigated(&(Fluffy.Frame.url(&1) == frame_url)))

    Playwright.evaluate(
      session,
      "url => { const f = document.createElement('iframe'); f.src = url; document.body.appendChild(f) }",
      arg: frame_url,
      is_function: true
    )

    await(frame_wait)
    event = Event.request(&String.ends_with?(&1.url, "/api"))
    page_wait = wait_for(session, event)
    context_wait = wait_for(session, event, scope: :context)

    Playwright.evaluate(session, "url => { document.querySelector('iframe').contentWindow.fetch(url); return true }",
      arg: TestHTTPFixtures.url(fixture, "/api"),
      is_function: true
    )

    request = await(page_wait)
    assert await(context_wait) == request
    assert request.page == current_page(session)
  end

  @tag driver: :playwright
  test "page waits stay bound while context waits include another page" do
    {original, fixture} = session()
    page_wait = wait_for(original, Event.request())
    context_wait = wait_for(original, Event.request(), scope: :context)
    other = switch_page(original, new_page(original))
    visit(other, TestHTTPFixtures.path(fixture, "/child"))
    other_request = await(context_wait)
    assert other_request.page == current_page(other)
    click(original, by_role(:button, name: "Save"))
    assert await(page_wait).page == current_page(original)
  end

  @tag driver: :playwright
  test "context scope observes a popup's initial request" do
    {session, fixture} = session()
    pending = wait_for(session, Event.request(&(&1.url == TestHTTPFixtures.url(fixture, "/child"))), scope: :context)
    popup = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Open child"))
    request = await(pending)
    assert request.method == "GET"
    assert request.resource_type == "document"
    # The context observes issuance before Playwright associates the new page.
    assert request.page == nil
    assert Fluffy.Page.opener(await(popup)) == current_page(session)
  end

  @tag driver: :playwright
  test "listener removal matches page or context scope" do
    {original, fixture} = session()
    other = switch_page(original, new_page(original))
    owner = self()
    handler = fn event -> send(owner, {:request, event.page}) end
    on(original, Event.request(), handler)
    on(original, Event.request(), handler, scope: :context)
    off(other, Event.request(), handler)
    visit(other, TestHTTPFixtures.path(fixture, "/child"))
    other_page = current_page(other)
    assert_receive {:request, ^other_page}
    off(other, Event.request(), handler, scope: :context)
    click(original, by_role(:button, name: "Save"))
    main_page = current_page(original)
    assert_receive {:request, ^main_page}
    refute_receive {:request, ^main_page}
    off(original, Event.request(), handler)
  end

  @tag driver: :playwright
  test "response waits resolve at headers before the body completes" do
    owner = self()

    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body:
                ~s|<button onclick="fetch('stream').then(r => r.text()).then(() => window.bodyComplete = true)">Fetch</button>|
            }

          "/stream" ->
            %{
              headers: [{"content-type", "text/plain"}],
              stream: fn conn ->
                {:ok, conn} = Plug.Conn.chunk(conn, "first")
                send(owner, {:stream, self()})

                receive do
                  :finish -> :ok
                after
                  5_000 -> :ok
                end

                {:ok, conn} = Plug.Conn.chunk(conn, "last")
                conn
              end
            }
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))

    pending = wait_for(session, Event.response(&String.ends_with?(&1.url, "/stream")))
    click(session, by_role(:button, name: "Fetch"))
    assert_receive {:stream, server}

    try do
      assert await(pending).status == 200
      refute Playwright.evaluate(session, "window.bodyComplete === true")
    after
      send(server, :finish)
    end
  end

  test "browser network support is validated before an action" do
    session = session_for_html(:static, "<button>Save</button>")

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        expect_event(session, Event.request(), fn _ -> flunk("unsupported action ran") end)
      end

    assert error.capability == :browser_network_events
  end

  defp session do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body: """
              <!doctype html><html><body>
              <button onclick="fetch('api?source=button', {method: 'POST', headers: {'x-fluffy': 'network-test'}, body: 'payload'})">Save</button>
              <a href="child" target="_blank">Open child</a>
              </body></html>
              """
            }

          "/child" ->
            %{body: "<h1>Child</h1>"}

          "/api" ->
            %{status: 207, headers: [{"content-type", "application/json"}], body: ~s({"saved":true})}
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))

    {session, fixture}
  end
end
