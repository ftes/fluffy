defmodule Fluffy.Conformance.StaticHTTPCookieTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.HTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "creates, scopes, replaces, and deletes cookies with #{driver}", %{driver: driver} do
      fixture = HTTPFixtures.register(&cookie_response/1)
      session = start_test_session(driver)

      visit(session, HTTPFixtures.path(fixture, "/account/set"))
      visit(session, HTTPFixtures.path(fixture, "/outside"))
      visit(session, HTTPFixtures.path(fixture, "/account/read"))
      visit(session, HTTPFixtures.path(fixture, "/replace"))
      visit(session, HTTPFixtures.path(fixture, "/read-replacement"))
      visit(session, HTTPFixtures.path(fixture, "/delete"))
      visit(session, HTTPFixtures.path(fixture, "/after-delete"))

      expect(session, "Cookie observation" |> by_text() |> to_be_visible())

      [_set, outside, account, replace, replaced, delete, deleted] =
        HTTPFixtures.requests(fixture)

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
        HTTPFixtures.register(fn request ->
          case request.path do
            "/set" ->
              %{headers: [{"set-cookie", "secret=alpha; Path=/"}], body: html()}

            "/read" ->
              %{body: html()}
          end
        end)

      first = start_test_session(driver)
      second = start_test_session(driver)

      visit(first, HTTPFixtures.path(fixture, "/set"))
      _second = visit(second, HTTPFixtures.path(fixture, "/read"))
      visit(first, HTTPFixtures.path(fixture, "/read"))

      [_set, second_read, first_read] = HTTPFixtures.requests(fixture)
      assert cookie_map(second_read) == %{}
      assert cookie_map(first_read) == %{"secret" => "alpha"}
    end

    @tag driver: driver
    if driver == :playwright, do: @tag(:webkit_difference)

    test "sends Secure cookies to the trustworthy loopback origin with #{driver}", %{
      driver: driver
    } do
      fixture =
        HTTPFixtures.register(fn request ->
          headers =
            if request.path == "/set",
              do: [{"set-cookie", "secure_session=present; Path=/; Secure; HttpOnly"}],
              else: []

          %{headers: headers, body: html()}
        end)

      session = start_test_session(driver)

      _session =
        session
        |> visit(HTTPFixtures.path(fixture, "/set"))
        |> visit(HTTPFixtures.path(fixture, "/read"))

      [_set, read] = HTTPFixtures.requests(fixture)

      if sends_secure_loopback_cookies?(driver),
        do: assert(cookie_map(read)["secure_session"] == "present"),
        else: refute(Map.has_key?(cookie_map(read), "secure_session"))
    end
  end

  # WebKit does not treat http loopback as trustworthy for Secure cookies (upstream Playwright
  # browsercontext-proxy.spec.ts PR-022 expects WebKit to omit them over http).
  defp sends_secure_loopback_cookies?(:playwright), do: not playwright_engine?(:webkit)
  defp sends_secure_loopback_cookies?(_driver), do: true

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
      base_url: Fluffy.Support.Server.base_url(),
      endpoint: Fluffy.Support.Web.Endpoint
    )
  end

  defp html do
    "<!doctype html><html><body><p>Cookie observation</p></body></html>"
  end
end
