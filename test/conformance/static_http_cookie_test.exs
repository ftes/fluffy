defmodule Fluffy.Conformance.StaticHTTPCookieTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "creates, scopes, replaces, and deletes cookies with #{driver}", %{driver: driver} do
      fixture = TestHTTPFixtures.register(&cookie_response/1)
      session = start_test_session(driver)

      session = visit(session, TestHTTPFixtures.path(fixture, "/account/set"))
      session = visit(session, TestHTTPFixtures.path(fixture, "/outside"))
      session = visit(session, TestHTTPFixtures.path(fixture, "/account/read"))
      session = visit(session, TestHTTPFixtures.path(fixture, "/replace"))
      session = visit(session, TestHTTPFixtures.path(fixture, "/read-replacement"))
      session = visit(session, TestHTTPFixtures.path(fixture, "/delete"))
      session = visit(session, TestHTTPFixtures.path(fixture, "/after-delete"))

      expect(session, visible(by_text("Cookie observation")))

      [_set, outside, account, replace, replaced, delete, deleted] =
        TestHTTPFixtures.requests(fixture)

      assert cookie_map(outside) == %{"root" => "one", "theme" => "light"}

      assert cookie_map(account) == %{
               "account" => "inside",
               "root" => "one",
               "theme" => "light"
             }

      assert cookie_map(replace)["theme"] == "light"
      assert cookie_map(replaced)["theme"] == "dark"
      assert cookie_map(delete)["theme"] == "dark"
      refute Map.has_key?(cookie_map(deleted), "theme")
      assert cookie_map(deleted)["root"] == "one"
    end

    @tag driver: driver
    test "isolates cookies between independent #{driver} sessions", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/set" ->
              %{headers: [{"set-cookie", "secret=alpha; Path=/"}], body: html()}

            "/read" ->
              %{body: html()}
          end
        end)

      first = start_test_session(driver)
      second = start_test_session(driver)

      first = visit(first, TestHTTPFixtures.path(fixture, "/set"))
      _second = visit(second, TestHTTPFixtures.path(fixture, "/read"))
      _first = visit(first, TestHTTPFixtures.path(fixture, "/read"))

      [_set, second_read, first_read] = TestHTTPFixtures.requests(fixture)
      assert cookie_map(second_read) == %{}
      assert cookie_map(first_read) == %{"secret" => "alpha"}
    end

    @tag driver: driver
    if driver == :playwright, do: @tag(:webkit_difference)

    test "sends Secure cookies to the trustworthy loopback origin with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register(fn request ->
          headers =
            if request.path == "/set",
              do: [{"set-cookie", "secure_session=present; Path=/; Secure; HttpOnly"}],
              else: []

          %{headers: headers, body: html()}
        end)

      session = start_test_session(driver)

      _session =
        session
        |> visit(TestHTTPFixtures.path(fixture, "/set"))
        |> visit(TestHTTPFixtures.path(fixture, "/read"))

      [_set, read] = TestHTTPFixtures.requests(fixture)
      assert cookie_map(read)["secure_session"] == "present"
    end
  end

  defp cookie_response(request) do
    fixture_path = String.trim_trailing(request.request_path, request.path)

    case request.path do
      "/account/set" ->
        %{
          headers: [
            {"set-cookie", "root=one; Path=#{fixture_path}/"},
            {"set-cookie", "account=inside; Path=#{fixture_path}/account"},
            {"set-cookie", "theme=light; Path=#{fixture_path}/"}
          ],
          body: html()
        }

      "/replace" ->
        %{headers: [{"set-cookie", "theme=dark; Path=#{fixture_path}/"}], body: html()}

      "/delete" ->
        %{
          headers: [{"set-cookie", "theme=gone; Path=#{fixture_path}/; Max-Age=0"}],
          body: html()
        }

      _path ->
        %{body: html()}
    end
  end

  defp cookie_map(request) do
    request.headers
    |> Enum.find_value("", fn
      {"cookie", value} -> value
      _header -> nil
    end)
    |> String.split(";", trim: true)
    |> Map.new(fn pair ->
      [name, value] = pair |> String.trim() |> String.split("=", parts: 2)
      {name, value}
    end)
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html do
    "<!doctype html><html><body><p>Cookie observation</p></body></html>"
  end
end
