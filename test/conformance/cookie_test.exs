defmodule Fluffy.Conformance.CookieTest do
  # Ports the cases of Playwright's browsercontext-add-cookies, -cookies and -clearcookies
  # specs that apply to both backends.
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Phoenix.ConnTest

  alias Fluffy.Support.HTTPFixtures

  @endpoint Fluffy.Support.Web.Endpoint

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "base_url/1 is the URL paths resolve against with #{driver}", %{driver: driver} do
      session = start_session(driver)
      assert base_url(session) == Fluffy.Support.Server.base_url()
      session |> visit(base_url(session) <> "/chamber") |> expect(page_to_have_url("/chamber"))
    end

    @tag driver: driver
    test "a cookie added with a url has Playwright's defaults with #{driver}", %{driver: driver} do
      session = add_cookies(start_session(driver), [%{name: "owl", value: "hedwig", url: "https://www.hogwarts.example"}])

      assert [cookie] = cookies(session, "https://www.hogwarts.example")

      assert Map.delete(cookie, :sameSite) == %{
               name: "owl",
               value: "hedwig",
               domain: "www.hogwarts.example",
               path: "/",
               expires: -1,
               httpOnly: false,
               secure: true
             }

      # Chromium's default, which Phoenix reports; Firefox and WebKit differ by platform.
      if driver == :phoenix or playwright_engine?(:chromium), do: assert(cookie.sameSite == "Lax")

      session = add_cookies(session, [%{name: "toad", value: "trevor", url: "http://hogwarts.example/owlery/post"}])

      assert [%{domain: "hogwarts.example", path: "/owlery/", secure: false}] =
               cookies(session, "http://hogwarts.example/owlery/")
    end

    @tag driver: driver
    test "round-trips expires, httpOnly, secure and sameSite with #{driver}", %{driver: driver} do
      expires = System.system_time(:second) + 3600

      session =
        add_cookies(start_session(driver), [
          %{
            name: "cloak",
            value: "invisible",
            domain: ".hogwarts.example",
            path: "/",
            expires: expires,
            httpOnly: true,
            secure: true,
            sameSite: "Strict"
          },
          %{name: "quill", value: "", domain: "hogwarts.example", path: "/", expires: -1, sameSite: "Lax"}
        ])

      assert [cloak, quill] = Enum.sort_by(cookies(session), & &1.name)
      assert %{domain: ".hogwarts.example", httpOnly: true, secure: true, sameSite: "Strict"} = cloak
      assert cloak.expires == expires
      assert %{value: "", expires: -1, httpOnly: false, secure: false, sameSite: "Lax"} = quill

      # A domain with a leading dot matches subdomains too (CO-010).
      assert ["cloak"] = session |> cookies("https://dungeons.hogwarts.example") |> Enum.map(& &1.name)
    end

    @tag driver: driver
    test "cookies(urls) returns the cookies a request to one of them would send with #{driver}", %{driver: driver} do
      session =
        add_cookies(start_session(driver), [
          %{name: "hostonly", value: "v", domain: "hogwarts.example", path: "/api", sameSite: "Lax"},
          %{name: "subdomains", value: "v", domain: ".hogwarts.example", path: "/api", sameSite: "Lax"},
          %{name: "slash", value: "v", domain: "hogwarts.example", path: "/owlery/", sameSite: "Lax"},
          %{name: "secret", value: "v", url: "https://gringotts.example", sameSite: "Lax"},
          %{name: "public", value: "v", url: "http://gringotts.example", sameSite: "Lax"}
        ])

      names = fn urls -> session |> cookies(urls) |> Enum.map(& &1.name) |> Enum.sort() end

      # CO-011
      assert names.("http://hogwarts.example/api") == ["hostonly", "subdomains"]
      assert names.("http://hogwarts.example/api/x") == ["hostonly", "subdomains"]
      assert names.("http://hogwarts.example/apiv2") == []
      assert names.("http://sub.hogwarts.example/api") == ["subdomains"]
      assert names.("http://nothogwarts.example/api") == []
      assert names.("http://hogwarts.example/owlery") == []
      assert names.("http://hogwarts.example/owlery/") == ["slash"]
      assert names.("http://hogwarts.example/owlery/hedwig") == ["slash"]
      # CO-013: a Secure cookie only for https.
      assert names.("https://gringotts.example") == ["public", "secret"]
      assert names.("http://gringotts.example/") == ["public"]
      # CO-009
      assert names.(["http://hogwarts.example/owlery/", "http://gringotts.example"]) == ["public", "slash"]
      assert length(cookies(session)) == 5
    end

    @tag driver: driver
    test "rejects invalid cookies as Playwright does, adding none with #{driver}", %{driver: driver} do
      session = start_session(driver)
      url = base_url(session)

      for {cookie, message} <- [
            {%{}, "Cookie should have a url or a domain/path pair"},
            {%{domain: "hogwarts.example"}, "Cookie should have a url or a domain/path pair"},
            {%{url: url, domain: "hogwarts.example"}, "Cookie should have either url or domain"},
            {%{url: url, path: "/"}, "Cookie should have either url or path"},
            {%{url: url, expires: -5}, "Cookie should have a valid expires"},
            {%{url: "about:blank"}, ~s(Blank page can not have cookie "spell")},
            {%{url: "data:,Hello"}, ~s(Data URL page can not have cookie "spell")}
          ] do
        cookie = Map.merge(%{name: "spell", value: "alohomora"}, cookie)
        error = catch_error(add_cookies(session, [%{name: "valid", value: "v", url: url}, cookie]))
        assert Exception.message(error) =~ message
      end

      assert cookies(session) == []
    end

    # As PlaywrightEx's nested objects: a key that is no cookie field, such as `http_only:`
    # for `httpOnly:`, raises instead of being dropped. Phoenix only until PlaywrightEx checks
    # `add_cookies`' keys.
    if driver == :phoenix do
      @tag driver: driver
      test "rejects an unknown cookie field, adding none with #{driver}", %{driver: driver} do
        session = start_session(driver)
        url = base_url(session)

        assert_raise ArgumentError,
                     ~r/browserContext.addCookies: unknown field :http_only, expected one of :domain, .*:httpOnly/,
                     fn ->
                       add_cookies(session, [
                         %{name: "valid", value: "v", url: url},
                         %{name: "spell", value: "x", url: url, http_only: true}
                       ])
                     end

        assert_raise ArgumentError, ~r/unknown field "same_site"/, fn ->
          add_cookies(session, [%{"name" => "spell", "value" => "x", "url" => url, "same_site" => "Lax"}])
        end

        assert cookies(session) == []
        add_cookies(session, [%{name: "spell", value: "x", url: url, partitionKey: "https://hogwarts.example"}])
        assert [%{name: "spell"}] = cookies(session)
      end
    end

    @tag driver: driver
    test "clears cookies by name, domain and path, as strings or regexes, with #{driver}", %{driver: driver} do
      cookies = [
        %{name: "fang", value: "1", domain: "hogwarts.example", path: "/"},
        %{name: "fang", value: "2", domain: "hogsmeade.example", path: "/"},
        %{name: "norbert", value: "3", domain: "hogwarts.example", path: "/dragons"},
        %{name: "aragog", value: "4", domain: "hogwarts.example", path: "/forest"}
      ]

      session = start_session(driver)

      remaining = fn options ->
        session
        |> clear_cookies()
        |> add_cookies(cookies)
        |> clear_cookies(options)
        |> cookies()
        |> Enum.map(&{&1.name, &1.value})
        |> Enum.sort()
      end

      # CO-044 to CO-048
      assert remaining.(name: "norbert") == [{"aragog", "4"}, {"fang", "1"}, {"fang", "2"}]
      assert remaining.(name: ~r/^(ara|nor)/) == [{"fang", "1"}, {"fang", "2"}]
      assert remaining.(domain: "hogsmeade.example") == [{"aragog", "4"}, {"fang", "1"}, {"norbert", "3"}]
      assert remaining.(path: "/forest") == [{"fang", "1"}, {"fang", "2"}, {"norbert", "3"}]
      assert remaining.(name: "fang", domain: ~r/^hogwarts/) == [{"aragog", "4"}, {"fang", "2"}, {"norbert", "3"}]
      assert remaining.([]) == []
    end

    @tag driver: driver
    test "requests send the cookies added before and after a visit with #{driver}", %{driver: driver} do
      fixture = HTTPFixtures.register(fn _request -> %{body: html()} end)
      session = start_session(driver)
      host = URI.parse(base_url(session)).host

      session =
        session
        |> add_cookies([%{name: "password", value: "caput-draconis", url: base_url(session)}])
        |> visit(HTTPFixtures.path(fixture, "/common-room"))
        |> add_cookies([
          %{name: "house", value: "gryffindor", url: base_url(session)},
          %{name: "dorm", value: "boys", domain: host, path: HTTPFixtures.path(fixture, "/dorm")}
        ])
        |> visit(HTTPFixtures.path(fixture, "/common-room"))
        |> visit(HTTPFixtures.path(fixture, "/dorm"))
        |> clear_cookies(name: "password")
        |> visit(HTTPFixtures.path(fixture, "/dorm"))

      expect(session, "Cookie observation" |> by_text() |> to_be_visible())

      assert Enum.map(HTTPFixtures.requests(fixture), &cookie_header/1) == [
               "password=caput-draconis",
               "password=caput-draconis; house=gryffindor",
               "dorm=boys; password=caput-draconis; house=gryffindor",
               "dorm=boys; house=gryffindor"
             ]
    end

    @tag driver: driver
    test "reports cookies the app set with #{driver}", %{driver: driver} do
      fixture =
        HTTPFixtures.register(fn _request ->
          %{
            headers: [
              {"set-cookie", "spell=lumos; Path=/; HttpOnly; SameSite=Strict"},
              {"set-cookie", "potion=felix; Path=/; Max-Age=3600; SameSite=Lax"}
            ],
            body: html()
          }
        end)

      session = start_session(driver)
      session = visit(session, HTTPFixtures.path(fixture, "/brew"))
      host = URI.parse(base_url(session)).host

      assert [potion, spell] = Enum.sort_by(cookies(session, base_url(session)), & &1.name)

      assert spell == %{
               name: "spell",
               value: "lumos",
               domain: host,
               path: "/",
               expires: -1,
               httpOnly: true,
               secure: false,
               sameSite: "Strict"
             }

      assert %{name: "potion", domain: ^host, httpOnly: false, sameSite: "Lax"} = potion
      assert_in_delta potion.expires, System.system_time(:second) + 3600, 5
    end

    # The login-without-UI recipe of docs/usage.md.
    @tag driver: driver
    test "logs in with a session cookie signed in-process with #{driver}", %{driver: driver} do
      session = start_session(driver)
      # As phx.gen.auth's `log_in_user/2`, then a request through the endpoint, whose
      # Plug.Session signs the session into its cookie.
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> Plug.Conn.put_session(:identity, "Hermione")
        |> get("/session/show")

      cookies = for {name, %{value: value}} <- conn.resp_cookies, do: %{name: name, value: value, url: base_url(session)}

      session
      |> add_cookies(cookies)
      |> visit("/session/show")
      |> expect("Static identity: Hermione" |> by_text() |> to_be_visible())
      |> visit("/live/session")
      |> expect("Live identity: Hermione" |> by_text() |> to_be_visible())
    end
  end

  defp cookie_header(request) do
    Enum.find_value(request.headers, "", fn
      {"cookie", value} -> value
      _header -> nil
    end)
  end

  defp html, do: "<!doctype html><html><body><p>Cookie observation</p></body></html>"
end
