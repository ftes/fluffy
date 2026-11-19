defmodule Fluffy.UseOptionsTest do
  use ExUnit.Case, async: true
  use Playwright.Test, locale: "en-GB", extra_http_headers: %{"x-house" => "hufflepuff"}

  import Fluffy
  import Fluffy.Expect

  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server

  # Playwright.Test resolves the options of every level; a session starts from them.
  test "the module's options reach the session" do
    {session, headers} = visit_page([])

    assert Fluffy.Playwright.evaluate(session, "navigator.language") == "en-GB"
    assert {"x-house", "hufflepuff"} in headers
  end

  describe "a describe's and a test's options" do
    @describetag Playwright.Test.use(viewport: %{width: 640, height: 480})

    # A level's `extra_http_headers` replaces those below it as a whole, as in Playwright.
    @tag Playwright.Test.use(color_scheme: :dark, extra_http_headers: %{"x-house" => "ravenclaw"})
    test "layer over the module's" do
      {session, headers} = visit_page([])

      assert Fluffy.Playwright.evaluate(
               session,
               "[navigator.language, innerWidth, matchMedia('(prefers-color-scheme: dark)').matches]"
             ) == ["en-GB", 640, true]

      assert {"x-house", "ravenclaw"} in headers
    end
  end

  # As in Playwright, a session's `extra_http_headers` replace the test's as a whole, on both
  # backends.
  for driver <- [:phoenix, :playwright] do
    test "the module's headers reach a #{driver} session, unless it has its own" do
      {_session, headers} = visit_page(unquote(driver), [])
      assert {"x-house", "hufflepuff"} in headers

      {_session, headers} = visit_page(unquote(driver), extra_http_headers: %{"x-wand" => "holly"})
      assert {"x-wand", "holly"} in headers
      refute Enum.any?(headers, &match?({"x-house", _value}, &1))
    end
  end

  # As a browser context, any pairs, a header without a value left out.
  @tag Playwright.Test.use(extra_http_headers: [{"X-Ghost", "nearly-headless-nick"}, {"x-house", nil}])
  test "a test's headers as pairs reach a Phoenix session, nil values left out" do
    {_session, headers} = visit_page(:phoenix, [])

    assert {"x-ghost", "nearly-headless-nick"} in headers
    refute Enum.any?(headers, &match?({"x-house", _value}, &1))
  end

  # As a browser context sends them: the locale as Accept-Language and the user agent as
  # User-Agent, under the test's headers, under the session's.
  describe "a Phoenix session's derived headers" do
    test "send the module's locale as Accept-Language" do
      {_session, headers} = visit_page(:phoenix, [])
      assert {"accept-language", "en-GB"} in headers
      refute Enum.any?(headers, &match?({"user-agent", _value}, &1))
    end

    @tag Playwright.Test.use(user_agent: "Errol/1.0")
    test "send the test's user agent as User-Agent" do
      {_session, headers} = visit_page(:phoenix, [])
      assert {"user-agent", "Errol/1.0"} in headers
    end

    @tag Playwright.Test.use(extra_http_headers: %{"accept-language" => "de-DE,de;q=0.9"})
    test "give way to the test's headers and to the session's" do
      {_session, headers} = visit_page(:phoenix, [])
      assert {"accept-language", "de-DE,de;q=0.9"} in headers

      {_session, headers} = visit_page(:phoenix, extra_http_headers: %{"Accept-Language" => "fr-FR"})
      assert {"accept-language", "fr-FR"} in headers
    end
  end

  # As Playwright's `baseURL`: relative visits resolve against it, over Fluffy's endpoint.
  describe "a test's base_url" do
    @describetag Playwright.Test.use(base_url: "http://hogwarts.test")

    test "is a Phoenix session's" do
      {session, _headers} = visit_page(:phoenix, [])
      expect(session, page_to_have_url(~r|^http://hogwarts\.test/__fluffy__/.*/common-room$|))
    end

    test "is a Playwright session's" do
      session = start_session(:playwright)

      Fluffy.Playwright.route(session, "http://hogwarts.test/**", fn route ->
        Playwright.Route.fulfill!(route, body: "<p>Great hall</p>", content_type: "text/html")
      end)

      session
      |> visit("/great-hall")
      |> expect(page_to_have_url("http://hogwarts.test/great-hall"))
    end

    test "gives way to the session's" do
      {session, _headers} = visit_page(:phoenix, base_url: Server.base_url())
      expect(session, page_to_have_url(~r|^#{Server.base_url()}/|))
    end
  end

  defp visit_page(driver \\ :playwright, options) do
    fixture = HTTPFixtures.register(fn _request -> %{body: "<p>Common room</p>"} end)
    session = driver |> start_session(options) |> visit(HTTPFixtures.path(fixture, "/common-room"))
    request = fixture |> HTTPFixtures.requests() |> Enum.find(&(&1.path == "/common-room"))
    {session, request.headers}
  end
end
