defmodule Fluffy.Conformance.StaticHTTPVisitTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Session
  alias Fluffy.TestHTTPFixtures
  alias Fluffy.TestWeb.Endpoint

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "visits one dynamic HTTP contract with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(%{
          status: 200,
          headers: [{"x-fluffy-case", "direct-visit"}],
          body: html("Dynamic order page")
        })

      session = start_test_session(driver)

      session =
        session
        |> visit(TestHTTPFixtures.path(fixture, "/orders?state=open#summary"))
        |> expect("Dynamic order page" |> by_text() |> to_be_visible())
        |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/orders?state=open#summary")))
        |> expect(Fluffy.Expect.page_to_have_url(~r|/orders\?state=open#summary$|))
        |> expect(not_(Fluffy.Expect.page_to_have_url(~r|/orders\?state=closed|)))

      assert Session.current_page(session).url ==
               TestHTTPFixtures.url(fixture, "/orders?state=open#summary")

      assert [request] = TestHTTPFixtures.requests(fixture)
      assert request.method == "GET"
      assert request.path == "/orders"
      assert request.query == "state=open"
      assert request.body == ""
    end

    @tag driver: driver
    test "follows relative redirects and commits only the final URL with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{status: 302, headers: [{"location", "middle?step=1"}]},
          %{status: 307, headers: [{"location", "final?done=yes#result"}]},
          %{body: html("Redirect destination")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start?from=visit#original"))
      |> expect("Redirect destination" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/final?done=yes#result")))

      assert Enum.map(TestHTTPFixtures.requests(fixture), fn request ->
               {request.method, request.path, request.query}
             end) == [
               {"GET", "/start", "from=visit"},
               {"GET", "/middle", "step=1"},
               {"GET", "/final", "done=yes"}
             ]
    end

    @tag driver: driver
    test "inherits the original fragment when a redirect omits one with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{status: 302, headers: [{"location", "destination"}]},
          %{body: html("Inherited fragment")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/source#details"))
      |> expect("Inherited fragment" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/destination#details")))
    end

    @tag driver: driver
    test "fails a redirect loop instead of retrying forever with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(%{
          status: 302,
          headers: [{"location", "loop"}]
        })

      session = start_test_session(driver)

      assert_raise RuntimeError, fn ->
        visit(session, TestHTTPFixtures.path(fixture, "/loop"))
      end

      assert length(TestHTTPFixtures.requests(fixture)) >= 20
    end

    @tag driver: driver
    test "keeps configured request headers for the #{driver} session", %{driver: driver} do
      fixture = TestHTTPFixtures.register(%{body: html("Header destination")})

      session =
        start_session(driver,
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Endpoint,
          headers: [{"x-fluffy-suite", "static-http"}]
        )

      session
      |> visit(TestHTTPFixtures.path(fixture, "/first"))
      |> visit(TestHTTPFixtures.path(fixture, "/second"))

      assert Enum.map(TestHTTPFixtures.requests(fixture), fn request ->
               Enum.find_value(request.headers, fn
                 {"x-fluffy-suite", value} -> value
                 _header -> nil
               end)
             end) == ["static-http", "static-http"]
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
  end

  defp html(text) do
    "<!doctype html><html><body><main><h1>#{text}</h1></main></body></html>"
  end
end
