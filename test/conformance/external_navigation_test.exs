defmodule Fluffy.Conformance.ExternalNavigationTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures
  alias Fluffy.TestWeb.Endpoint

  @three_broomsticks "https://hogsmeade.example/three-broomsticks"

  # A browser really loads the external page, so Playwright stubs its host.
  defp hogsmeade_session(:phoenix), do: start_test_session(:phoenix)

  defp hogsmeade_session(:playwright) do
    session = start_test_session(:playwright)

    Fluffy.Playwright.route(session, "https://hogsmeade.example/**", fn route ->
      PlaywrightEx.Route.fulfill!(route, content_type: "text/html", body: "<h1>The Three Broomsticks</h1>")
    end)

    session
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "an off-origin link ends at its URL from a static page with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(%{body: html(~s(<a href="#{@three_broomsticks}?from=link">The Three Broomsticks</a>))})

      driver
      |> hogsmeade_session()
      |> visit(TestHTTPFixtures.path(fixture, "/source"))
      |> click(by_role(:link, name: "The Three Broomsticks"))
      |> expect(page_to_have_url(@three_broomsticks <> "?from=link"))
    end

    @tag driver: driver
    test "a visit whose response redirects off-origin ends at the redirect's location with #{driver}",
         %{driver: driver} do
      ministry_url = cross_origin_ministry("/floo?from=visit")
      fixture = TestHTTPFixtures.register(%{status: 302, headers: [{"location", ministry_url}]})

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/auth"))
      |> expect(page_to_have_url(ministry_url))
    end

    @tag driver: driver
    test "a form posting to another origin ends at its action with #{driver}", %{driver: driver} do
      ministry_url = cross_origin_ministry("/floo?from=form")

      fixture =
        TestHTTPFixtures.register(%{
          body: html(~s(<form method="post" action="#{ministry_url}"><button>Floo to the Ministry</button></form>))
        })

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> click(by_role(:button, name: "Floo to the Ministry"))
      |> expect(page_to_have_url(ministry_url))
    end

    @tag driver: driver
    test "a form whose response redirects off-origin ends at the redirect's location with #{driver}",
         %{driver: driver} do
      ministry_url = cross_origin_ministry("/floo?from=redirect")

      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<form method="post" action="floo"><button>Floo to the Ministry</button></form>))},
          %{status: 302, headers: [{"location", ministry_url}]}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> click(by_role(:button, name: "Floo to the Ministry"))
      |> expect(page_to_have_url(ministry_url))
    end

    @tag driver: driver
    test "LiveView links and external redirects end at the external URL with #{driver}", %{driver: driver} do
      session = hogsmeade_session(driver)

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:link, name: "The Three Broomsticks"))
      |> expect(page_to_have_url(@three_broomsticks <> "?from=link"))

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:button, name: "Visit Hogsmeade"))
      |> expect(page_to_have_url(@three_broomsticks <> "?from=event"))

      session
      |> visit("/live/chamber-map?redirect=external")
      |> expect(page_to_have_url(@three_broomsticks <> "?from=mount"))
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "a LiveView external redirect reads as the browser's URL and keeps its flash for the app with #{driver}",
         %{driver: driver} do
      driver
      |> hogsmeade_session()
      |> visit("/live/chamber-map")
      |> click(by_role(:button, name: "Send news to Hogsmeade"))
      |> expect(page_to_have_url("https://hogsmeade.example/?from=flash"))
      |> visit("/live/secret-chamber")
      |> expect("Off to Hogsmeade" |> by_text() |> to_be_visible())
    end
  end

  # Hosts are case-insensitive. The test server's 127.0.0.1 has no case, so the session names it localhost.
  test "a Phoenix link to the app's host in another case stays in the app" do
    base_url = %{URI.parse(Fluffy.TestServer.base_url()) | host: "localhost"}
    next = TestHTTPFixtures.register(%{body: html("<h1>Next page</h1>")})
    next_url = URI.to_string(%{base_url | host: "LOCALHOST", path: TestHTTPFixtures.path(next)})
    source = TestHTTPFixtures.register(%{body: html(~s(<a href="#{next_url}">Next</a>))})

    :phoenix
    |> start_session(base_url: URI.to_string(base_url), endpoint: Endpoint)
    |> visit(TestHTTPFixtures.path(source))
    |> click(by_role(:link, name: "Next"))
    |> expect("Next page" |> by_text() |> to_be_visible())
  end

  describe "on Phoenix, the external page" do
    setup do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<form method="post" action="floo"><button>Floo to the Ministry</button></form>))},
          %{status: 302, headers: [{"location", @three_broomsticks <> "?from=redirect"}]},
          %{body: html("<h1>Back home</h1>")}
        ])

      session =
        :phoenix
        |> start_test_session()
        |> visit(TestHTTPFixtures.path(fixture, "/start"))
        |> click(by_role(:button, name: "Floo to the Ministry"))

      %{fixture: fixture, session: session}
    end

    test "raises :external_navigation for anything that needs a document", %{session: session} do
      heading = by_role(:heading)

      for operation <- [
            fn -> click(session, heading) end,
            fn -> fill(session, by_label("Email"), "user@hogwarts.example") end,
            fn -> submit(session, by_css("form")) end,
            fn -> press(session, heading, "Enter") end,
            fn -> reload(session) end,
            fn -> open_browser(session, fn _path -> :ok end) end,
            fn -> expect(session, page_to_have_title("Hogsmeade")) end,
            fn -> expect(session, heading |> to_be_visible() |> not_()) end,
            fn -> Fluffy.Assert.refute_has(session, heading) end,
            fn -> unwrap(session, & &1) end,
            fn -> unwrap_and_return(session, & &1) end
          ] do
        assert_raise Fluffy.CapabilityError, ~r/external_navigation.*#{Regex.escape(@three_broomsticks)}/, operation
      end
    end

    test "visits back into the app", %{fixture: fixture, session: session} do
      session
      |> visit(TestHTTPFixtures.path(fixture, "/home"))
      |> expect("Back home" |> by_text() |> to_be_visible())
    end
  end

  # Playwright routes only a redirect's first URL, so these tests reach the test server under
  # another origin instead, like Playwright's own CROSS_PROCESS_PREFIX: Phoenix stops there and
  # Playwright loads the page.
  defp cross_origin_ministry(suffix) do
    ministry = TestHTTPFixtures.register(%{body: html("<h1>Ministry of Magic</h1>")})
    url = %{URI.parse(TestHTTPFixtures.url(ministry, suffix)) | host: "localhost"}
    assert url.host != URI.parse(Fluffy.TestServer.base_url()).host
    URI.to_string(url)
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
  end

  defp html(body), do: "<!doctype html><html><head><title>Fixture</title></head><body>#{body}</body></html>"
end
