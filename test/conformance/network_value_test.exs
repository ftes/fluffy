defmodule Fluffy.Conformance.NetworkValueTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.Playwright
  alias Fluffy.Request
  alias Fluffy.Response
  alias Fluffy.TestHTTPFixtures

  @tag driver: :playwright
  test "a response reads its body as bytes, text and JSON" do
    {session, _fixture} = session()
    response = response(session, "Save", "/api")

    assert Response.ok?(response)
    assert Response.body(response) == ~s({"saved":true})
    assert Response.text(response) == ~s({"saved":true})
    assert Response.json(response) == %{"saved" => true}
  end

  @tag driver: :playwright
  test "ok? is false outside the 2xx range" do
    {session, _fixture} = session()
    response = response(session, "Missing", "/missing")

    assert response.status == 404
    refute Response.ok?(response)
    assert Response.text(response) == "not json"
  end

  @tag driver: :playwright
  test "json raises on a body that is not JSON" do
    {session, _fixture} = session()
    response = response(session, "Missing", "/missing")

    assert_raise JSON.DecodeError, fn -> Response.json(response) end
  end

  @tag driver: :playwright
  test "a response's header readers include repeated and security-related headers" do
    {session, _fixture} = session()
    response = response(session, "Cookies", "/cookies")

    all_headers = Response.all_headers(response)
    assert all_headers["x-custom"] == "value"
    assert all_headers["set-cookie"] =~ "first=1"
    assert Response.header_value(response, "X-Custom") == "value"
    assert Response.header_value(response, "x-absent") == nil
    assert Response.header_value(response, "set-cookie") =~ "second=2"
    assert [_ | _] = values = Response.header_values(response, "Set-Cookie")
    assert Enum.join(values, "\n") =~ "first=1"
    assert Response.header_values(response, "x-absent") == []
  end

  @tag driver: :playwright
  test "a request's header readers match case-insensitively" do
    {session, _fixture} = session()
    %Response{request: request} = response(session, "Save", "/api")

    assert Request.all_headers(request)["x-fluffy"] == "network-test"
    assert Request.header_value(request, "X-Fluffy") == "network-test"
    assert Request.header_value(request, "x-absent") == nil
  end

  @tag driver: :playwright
  test "post_data_json parses JSON and form bodies" do
    {session, fixture} = session()

    assert post_data_json(session, fixture, "{'content-type': 'application/json'}", ~s('{"a":1}')) == %{"a" => 1}

    assert post_data_json(session, fixture, "{'content-type': 'application/x-www-form-urlencoded'}", "'a=1&b=2'") ==
             %{"a" => "1", "b" => "2"}

    %Response{request: without_body} = response(session, "Get", "/get")
    assert Request.post_data_json(without_body) == nil
  end

  @tag driver: :playwright
  test "post_data_json raises on a body that is not JSON" do
    {session, _fixture} = session()
    %Response{request: request} = response(session, "Save", "/api")

    assert_raise RuntimeError, ~r/not a valid JSON/, fn -> Request.post_data_json(request) end
  end

  @tag driver: :playwright
  test "failure is nil for a request that succeeded and reports one that failed" do
    {session, fixture} = session()
    %Response{request: succeeded} = response(session, "Save", "/api")
    assert Request.failure(succeeded) == nil

    url = TestHTTPFixtures.url(fixture, "/hanging")
    pending = wait_for(session, Event.request(&(&1.url == url)))

    assert Playwright.evaluate(
             session,
             """
             async url => {
               const controller = new AbortController()
               const response = await fetch(url, {signal: controller.signal})
               controller.abort()
               return response.text().catch(() => 'aborted')
             }
             """,
             url
           ) == "aborted"

    request = await(pending)
    # The browser reports the failure after the page sees the fetch reject.
    assert_eventually(fn -> Request.failure(request) != nil end)
    assert %{errorText: reason} = Request.failure(request)
    assert is_binary(reason)
  end

  @tag driver: :playwright
  test "redirected_from and redirected_to walk a redirect chain as Fluffy requests" do
    {session, _fixture} = session()
    %Response{request: final} = response(session, "Redirect", "/final")

    assert %Request{} = first = Request.redirected_from(final)
    assert String.ends_with?(first.url, "/redirect")
    assert first.page == current_page(session)
    assert Request.redirected_from(first) == nil
    assert Request.redirected_to(first) == final
    assert Request.redirected_to(final) == nil
  end

  @tag driver: :playwright
  test "readers raise once the session is closed, even for a request without a page" do
    {session, fixture} = session()
    response = response(session, "Save", "/api")

    popup_request =
      wait_for(session, Event.request(&(&1.url == TestHTTPFixtures.url(fixture, "/child"))), scope: :context)

    popup = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Open child"))
    assert %Request{page: nil} = request = await(popup_request)
    await(popup)
    close_session(session)

    for read <- [
          fn -> Response.body(response) end,
          fn -> Response.text(response) end,
          fn -> Response.json(response) end,
          fn -> Response.all_headers(response) end,
          fn -> Response.header_value(response, "x") end,
          fn -> Response.header_values(response, "x") end,
          fn -> Request.all_headers(request) end,
          fn -> Request.header_value(request, "x") end,
          fn -> Request.post_data_json(request) end,
          fn -> Request.failure(request) end,
          fn -> Request.redirected_from(request) end,
          fn -> Request.redirected_to(request) end
        ] do
      assert_raise ArgumentError, ~r/session is closed/, read
    end

    assert Response.ok?(response)
  end

  defp response(session, button, suffix) do
    pending = wait_for(session, Event.response(&String.ends_with?(&1.url, suffix)))
    click(session, by_role(:button, name: button, exact: true))
    await(pending)
  end

  defp post_data_json(session, fixture, headers, body) do
    url = TestHTTPFixtures.url(fixture, "/echo")
    pending = wait_for(session, Event.request(&(&1.url == url)))

    Playwright.evaluate(
      session,
      "url => { fetch(url, {method: 'POST', headers: #{headers}, body: #{body}}); return true }",
      url
    )

    Request.post_data_json(await(pending))
  end

  defp session do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body: """
              <!doctype html><html><body>
              <button onclick="fetch('api', {method: 'POST', headers: {'x-fluffy': 'network-test'}, body: 'payload'})">Save</button>
              <button onclick="fetch('missing')">Missing</button>
              <button onclick="fetch('cookies')">Cookies</button>
              <button onclick="fetch('get')">Get</button>
              <button onclick="fetch('redirect')">Redirect</button>
              <a href="child" target="_blank">Open child</a>
              </body></html>
              """
            }

          "/child" ->
            %{body: "<h1>Child</h1>"}

          "/api" ->
            %{headers: [{"content-type", "application/json"}], body: ~s({"saved":true})}

          "/missing" ->
            %{status: 404, headers: [{"content-type", "text/plain"}], body: "not json"}

          "/cookies" ->
            %{
              headers: [{"x-custom", "value"}, {"set-cookie", "first=1"}, {"set-cookie", "second=2"}],
              body: "ok"
            }

          "/get" ->
            %{body: "ok"}

          "/echo" ->
            %{body: "ok"}

          "/hanging" ->
            %{
              headers: [{"content-type", "text/plain"}],
              stream: fn conn ->
                {:ok, conn} = Plug.Conn.chunk(conn, "first")
                Process.sleep(500)
                conn
              end
            }

          "/redirect" ->
            %{status: 302, headers: [{"location", "final"}], body: "redirect"}

          "/final" ->
            %{headers: [{"content-type", "text/plain"}], body: "final"}
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))

    {session, fixture}
  end
end
