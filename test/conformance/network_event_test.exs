defmodule Fluffy.Conformance.NetworkEventTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.Playwright
  alias Fluffy.SessionRuntime
  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server
  alias PlaywrightEx.Request
  alias PlaywrightEx.Response

  @tag driver: :playwright
  test "request and response events deliver PlaywrightEx's values" do
    {session, fixture} = session()
    request_wait = wait_for(session, Event.request(&String.ends_with?(url(&1), "/api?source=button")))
    response_wait = wait_for(session, Event.response(&String.ends_with?(url(&1), "/api?source=button")))
    click(session, by_role(:button, name: "Save"))

    assert %Request{} = request = await(request_wait)
    assert {Request.method(request), Request.resource_type(request)} == {"POST", "fetch"}
    assert Request.post_data(request) == "payload"
    assert Request.url(request) == HTTPFixtures.url(fixture, "/api?source=button")
    assert Request.headers(request)["x-fluffy"] == "network-test"
    assert request_page(session, request) == current_page(session)

    assert %Response{} = response = await(response_wait)
    assert {Response.status(response), Response.status_text(response)} == {207, "Multi-Status"}
    assert Response.headers(response)["content-type"] == "application/json"
    assert Response.request(response) == request
    assert Response.text!(response) == ~s({"saved":true})
  end

  @tag driver: :playwright
  test "a request's post_data keeps a binary body's bytes" do
    {session, fixture} = session()
    request_wait = wait_for(session, Event.request(&String.ends_with?(url(&1), "/api?source=bytes")))

    Playwright.evaluate(
      session,
      "url => { fetch(url, {method: 'POST', body: new Uint8Array([0xff, 0x00, 0x89, 0x50])}); return true }",
      HTTPFixtures.url(fixture, "/api?source=bytes")
    )

    assert Request.post_data_buffer(await(request_wait)) == <<0xFF, 0x00, 0x89, 0x50>>
  end

  @tag driver: :playwright
  test "page and context waits observe the same request, including child-frame requests" do
    {session, fixture} = session()
    frame_url = HTTPFixtures.url(fixture, "/child")
    frame_wait = wait_for(session, Event.frame_navigated(&(PlaywrightEx.Frame.url(&1) == frame_url)))

    Playwright.evaluate(
      session,
      "url => { const f = document.createElement('iframe'); f.src = url; document.body.appendChild(f) }",
      frame_url
    )

    await(frame_wait)
    event = Event.request(&String.ends_with?(url(&1), "/api"))
    page_wait = wait_for(session, event)
    context_wait = wait_for(session, event, scope: :context)

    Playwright.evaluate(
      session,
      "url => { document.querySelector('iframe').contentWindow.fetch(url); return true }",
      HTTPFixtures.url(fixture, "/api")
    )

    request = await(page_wait)
    assert await(context_wait) == request
    assert request_page(session, request) == current_page(session)
  end

  @tag driver: :playwright
  test "page waits stay bound while context waits include another page" do
    {original, fixture} = session()
    page_wait = wait_for(original, Event.request())
    context_wait = wait_for(original, Event.request(), scope: :context)
    other = switch_page(original, new_page(original))
    visit(other, HTTPFixtures.path(fixture, "/child"))
    assert request_page(original, await(context_wait)) == current_page(other)
    click(original, by_role(:button, name: "Save"))
    assert request_page(original, await(page_wait)) == current_page(original)
  end

  @tag driver: :playwright
  test "context scope observes a popup's initial request" do
    {session, fixture} = session()
    pending = wait_for(session, Event.request(&(url(&1) == HTTPFixtures.url(fixture, "/child"))), scope: :context)
    popup = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Open child"))
    request = await(pending)
    assert {Request.method(request), Request.resource_type(request)} == {"GET", "document"}
    # The context observes issuance before Playwright associates the new page.
    assert_raise RuntimeError, fn -> Request.frame(request) end
    assert Fluffy.Page.opener(await(popup)) == current_page(session)
  end

  # Holding the session runtime while the popup opens and closes keeps Fluffy
  # from registering the popup, as when it closes before Fluffy sees it.
  @tag driver: :playwright
  test "a context wait ignores an event from a page that closed before Fluffy saw it" do
    {session, _fixture} = session()
    pending = wait_for(session, Event.response(&String.ends_with?(url(&1), "/api?source=last")), scope: :context)
    frame = Fluffy.Session.page_state(session).frame
    owner = self()

    holder =
      Task.async(fn ->
        SessionRuntime.run(session.runtime, fn ->
          send(owner, :held)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :held

    assert {:ok, nil} =
             PlaywrightEx.Frame.evaluate(frame, """
             async () => {
               const popup = window.open('closing')
               while (!popup.closed) await new Promise(resolve => setTimeout(resolve, 20))
               await fetch('api?source=last')
             }
             """)

    send(session.runtime, :release)
    Task.await(holder)
    assert request_page(session, Response.request(await(pending))) == current_page(session)
  end

  @tag driver: :playwright
  test "listener removal matches page or context scope" do
    {original, fixture} = session()
    other = switch_page(original, new_page(original))
    owner = self()
    handler = fn request -> send(owner, {:request, request_page(original, request)}) end
    on(original, Event.request(), handler)
    on(original, Event.request(), handler, scope: :context)
    off(other, Event.request(), handler)
    visit(other, HTTPFixtures.path(fixture, "/child"))
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
      HTTPFixtures.register(fn request ->
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
      |> start_session(base_url: Server.base_url())
      |> visit(HTTPFixtures.path(fixture, "/start"))

    pending = wait_for(session, Event.response(&String.ends_with?(url(&1), "/stream")))
    click(session, by_role(:button, name: "Fetch"))
    assert_receive {:stream, server}, 5_000

    try do
      assert Response.status(await(pending)) == 200
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

  defp url(%Request{} = request), do: Request.url(request)
  defp url(%Response{} = response), do: Response.url(response)

  defp request_page(session, request), do: page(session, PlaywrightEx.Frame.page(Request.frame(request)))

  defp session do
    fixture =
      HTTPFixtures.register(fn request ->
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

          "/closing" ->
            %{body: "<script>fetch('api?source=popup').then(() => window.close())</script>"}

          "/api" ->
            %{status: 207, headers: [{"content-type", "application/json"}], body: ~s({"saved":true})}
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Server.base_url())
      |> visit(HTTPFixtures.path(fixture, "/start"))

    {session, fixture}
  end
end
