defmodule Fluffy.Conformance.StaticHTTPVisitTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Session
  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "visits one dynamic HTTP contract with #{driver}", %{driver: driver} do
      fixture =
        HTTPFixtures.register(%{
          status: 200,
          headers: [{"x-fluffy-case", "direct-visit"}],
          body: html("Dynamic owl page")
        })

      session = start_test_session(driver)

      session =
        session
        |> visit(HTTPFixtures.path(fixture, "/owls?state=open#summary"))
        |> expect("Dynamic owl page" |> by_text() |> to_be_visible())
        |> expect(Fluffy.Expect.page_to_have_url(HTTPFixtures.url(fixture, "/owls?state=open#summary")))
        |> expect(Fluffy.Expect.page_to_have_url(~r|/owls\?state=open#summary$|))
        |> expect(not_(Fluffy.Expect.page_to_have_url(~r|/owls\?state=closed|)))

      assert Session.current_page(session).url ==
               HTTPFixtures.url(fixture, "/owls?state=open#summary")

      assert [request] = HTTPFixtures.requests(fixture)
      assert request.method == "GET"
      assert request.path == "/owls"
      assert request.query == "state=open"
      assert request.body == ""
    end

    @tag driver: driver
    test "follows relative redirects and commits only the final URL with #{driver}", %{
      driver: driver
    } do
      fixture =
        HTTPFixtures.register_sequence([
          %{status: 302, headers: [{"location", "middle?step=1"}]},
          %{status: 307, headers: [{"location", "final?done=yes#result"}]},
          %{body: html("Redirect destination")}
        ])

      session = start_test_session(driver)

      session
      |> visit(HTTPFixtures.path(fixture, "/start?from=visit#original"))
      |> expect("Redirect destination" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(HTTPFixtures.url(fixture, "/final?done=yes#result")))

      assert Enum.map(HTTPFixtures.requests(fixture), fn request ->
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
        HTTPFixtures.register_sequence([
          %{status: 302, headers: [{"location", "destination"}]},
          %{body: html("Inherited fragment")}
        ])

      session = start_test_session(driver)

      session
      |> visit(HTTPFixtures.path(fixture, "/source#details"))
      |> expect("Inherited fragment" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(HTTPFixtures.url(fixture, "/destination#details")))
    end

    @tag driver: driver
    test "fails a redirect loop instead of retrying forever with #{driver}", %{driver: driver} do
      fixture =
        HTTPFixtures.register(%{
          status: 302,
          headers: [{"location", "loop"}]
        })

      session = start_test_session(driver)

      assert_raise navigation_error(driver), fn ->
        visit(session, HTTPFixtures.path(fixture, "/loop"))
      end

      assert length(HTTPFixtures.requests(fixture)) >= 20
    end

    # The browser aborts the navigation and stays where it was; Playwright's goto fails.
    for status <- [204, 205] do
      @tag driver: driver
      test "visit fails on a #{status} response with #{driver}", %{driver: driver} do
        fixture =
          HTTPFixtures.register_sequence([
            %{status: unquote(status)},
            %{body: html("Owls")},
            %{status: unquote(status)}
          ])

        assert_raise navigation_error(driver), ~r/abort|interrupt/i, fn ->
          driver |> start_test_session() |> visit(HTTPFixtures.path(fixture, "/empty"))
        end

        session = driver |> start_test_session() |> visit(HTTPFixtures.path(fixture, "/owls"))

        assert_raise navigation_error(driver), ~r/abort|interrupt/i, fn ->
          visit(session, HTTPFixtures.path(fixture, "/empty"))
        end

        assert Enum.map(HTTPFixtures.requests(fixture), & &1.path) == ["/empty", "/owls", "/empty"]
      end

      @tag driver: driver
      test "a failed visit keeps the cookies of its #{status} response with #{driver}", %{driver: driver} do
        fixture =
          HTTPFixtures.register_sequence([
            %{body: html("Owls")},
            %{status: unquote(status), headers: [{"set-cookie", "seen=1; Path=/"}]},
            %{body: html("Owls")}
          ])

        session = driver |> start_test_session() |> visit(HTTPFixtures.path(fixture, "/owls"))

        assert_raise navigation_error(driver), ~r/abort|interrupt/i, fn ->
          visit(session, HTTPFixtures.path(fixture, "/beacon"))
        end

        visit(session, HTTPFixtures.path(fixture, "/owls"))

        assert [_owls, _beacon, %{headers: headers}] = HTTPFixtures.requests(fixture)
        assert {"cookie", "seen=1"} in headers
      end
    end

    @tag driver: driver
    test "keeps configured request headers for the #{driver} session", %{driver: driver} do
      fixture = HTTPFixtures.register(%{body: html("Header destination")})

      session =
        start_session(driver,
          base_url: Server.base_url(),
          endpoint: Endpoint,
          headers: [{"x-fluffy-suite", "static-http"}]
        )

      session
      |> visit(HTTPFixtures.path(fixture, "/first"))
      |> visit(HTTPFixtures.path(fixture, "/second"))

      assert Enum.map(HTTPFixtures.requests(fixture), fn request ->
               Enum.find_value(request.headers, fn
                 {"x-fluffy-suite", value} -> value
                 _header -> nil
               end)
             end) == ["static-http", "static-http"]
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Server.base_url(),
      endpoint: Endpoint
    )
  end

  defp html(text) do
    "<!doctype html><html><body><main><h1>#{text}</h1></main></body></html>"
  end

  # Playwright raises its own exception for a failed navigation.
  defp navigation_error(:playwright), do: Fluffy.OperationError
  defp navigation_error(:phoenix), do: RuntimeError
end
