defmodule Fluffy.Conformance.ExternalNavigationTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures

  @guild "https://guild.example/hall"

  # A browser really loads the external page, so Playwright stubs its host.
  defp guild_session(:phoenix), do: start_test_session(:phoenix)

  defp guild_session(:playwright) do
    session = start_test_session(:playwright)

    Fluffy.Playwright.route(session, "https://guild.example/**", fn route ->
      Fluffy.Route.fulfill(route, content_type: "text/html", body: "<h1>Guild hall</h1>")
    end)

    session
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "an off-origin link ends at its URL from a static page with #{driver}", %{driver: driver} do
      fixture = TestHTTPFixtures.register(%{body: html(~s(<a href="#{@guild}?from=link">Guild hall</a>))})

      driver
      |> guild_session()
      |> visit(TestHTTPFixtures.path(fixture, "/source"))
      |> click(by_role(:link, name: "Guild hall"))
      |> expect(page_to_have_url(@guild <> "?from=link"))
    end

    @tag driver: driver
    test "a form posting to another origin ends at its action with #{driver}", %{driver: driver} do
      hall_url = cross_origin_hall("/hall?from=form")

      fixture =
        TestHTTPFixtures.register(%{
          body: html(~s(<form method="post" action="#{hall_url}"><button>Sign in</button></form>))
        })

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> click(by_role(:button, name: "Sign in"))
      |> expect(page_to_have_url(hall_url))
    end

    @tag driver: driver
    test "a form whose response redirects off-origin ends at the redirect's location with #{driver}",
         %{driver: driver} do
      hall_url = cross_origin_hall("/hall?from=redirect")

      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<form method="post" action="login"><button>Sign in</button></form>))},
          %{status: 302, headers: [{"location", hall_url}]}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> click(by_role(:button, name: "Sign in"))
      |> expect(page_to_have_url(hall_url))
    end

    @tag driver: driver
    test "LiveView links and external redirects end at the external URL with #{driver}", %{driver: driver} do
      session = guild_session(driver)

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:link, name: "Guild hall"))
      |> expect(page_to_have_url(@guild <> "?from=link"))

      session
      |> visit("/live/chamber-map")
      |> click(by_role(:button, name: "Visit the guild"))
      |> expect(page_to_have_url(@guild <> "?from=event"))

      session
      |> visit("/live/chamber-map?redirect=external")
      |> expect(page_to_have_url(@guild <> "?from=mount"))
    end
  end

  describe "on Phoenix, the external page" do
    setup do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<form method="post" action="login"><button>Sign in</button></form>))},
          %{status: 302, headers: [{"location", @guild <> "?from=redirect"}]},
          %{body: html("<h1>Back home</h1>")}
        ])

      session =
        :phoenix
        |> start_test_session()
        |> visit(TestHTTPFixtures.path(fixture, "/start"))
        |> click(by_role(:button, name: "Sign in"))

      %{fixture: fixture, session: session}
    end

    test "raises :external_navigation for anything that needs a document", %{session: session} do
      heading = by_role(:heading)

      for operation <- [
            fn -> click(session, heading) end,
            fn -> fill(session, by_label("Email"), "user@example.com") end,
            fn -> submit(session, by_css("form")) end,
            fn -> press(session, heading, "Enter") end,
            fn -> reload(session) end,
            fn -> open_browser(session, fn _path -> :ok end) end,
            fn -> expect(session, page_to_have_title("Guild")) end,
            fn -> expect(session, heading |> to_be_visible() |> not_()) end,
            fn -> Fluffy.Assert.refute_has(session, heading) end,
            fn -> unwrap(session, & &1) end,
            fn -> unwrap_and_return(session, & &1) end
          ] do
        assert_raise Fluffy.CapabilityError, ~r/external_navigation.*#{Regex.escape(@guild)}/, operation
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
  defp cross_origin_hall(suffix) do
    hall = TestHTTPFixtures.register(%{body: html("<h1>Guild hall</h1>")})
    url = %{URI.parse(TestHTTPFixtures.url(hall, suffix)) | host: "localhost"}
    assert url.host != URI.parse(Fluffy.TestServer.base_url()).host
    URI.to_string(url)
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body), do: "<!doctype html><html><head><title>Fixture</title></head><body>#{body}</body></html>"
end
