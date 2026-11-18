defmodule Fluffy.UseOptionsTest do
  use ExUnit.Case, async: true
  use Playwright.Test, locale: "en-GB", extra_http_headers: %{"x-house" => "hufflepuff"}

  import Fluffy
  import Fluffy.Expect

  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server

  # Playwright.Test resolves the options of every level; a session starts from them.
  test "the module's options reach the session, its headers merged with the session's" do
    {session, headers} = visit_page(headers: [{"x-wand", "holly"}])

    assert Fluffy.Playwright.evaluate(session, "navigator.language") == "en-GB"
    assert {"x-house", "hufflepuff"} in headers
    assert {"x-wand", "holly"} in headers
  end

  describe "a describe's and a test's options" do
    @describetag Playwright.Test.use(viewport: %{width: 640, height: 480})

    # A level's `extra_http_headers` replaces those below it as a whole, as in Playwright.
    @tag Playwright.Test.use(color_scheme: :dark, extra_http_headers: %{"x-house" => "ravenclaw"})
    test "layer over the module's" do
      {session, headers} = visit_page(headers: [{"x-wand", "holly"}])

      assert Fluffy.Playwright.evaluate(
               session,
               "[navigator.language, innerWidth, matchMedia('(prefers-color-scheme: dark)').matches]"
             ) == ["en-GB", 640, true]

      assert {"x-house", "ravenclaw"} in headers
      assert {"x-wand", "holly"} in headers
    end
  end

  # As a browser context's, the test's headers go with a Phoenix session's requests, under its own.
  test "the module's headers reach a Phoenix session, merged with the session's" do
    {_session, headers} = visit_page(:phoenix, headers: [{"x-wand", "holly"}])

    assert {"x-house", "hufflepuff"} in headers
    assert {"x-wand", "holly"} in headers

    {_session, headers} = visit_page(:phoenix, headers: [{"x-house", "slytherin"}])
    assert {"x-house", "slytherin"} in headers
    refute {"x-house", "hufflepuff"} in headers
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
