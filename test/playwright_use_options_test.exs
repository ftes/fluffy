defmodule Fluffy.PlaywrightUseOptionsTest do
  use ExUnit.Case, async: true
  use Fluffy.Case, locale: "en-GB", extra_http_headers: %{"x-house" => "hufflepuff"}

  import Fluffy

  alias Fluffy.Support.HTTPFixtures

  # Playwright.Test resolves the options of every level; the session's context starts from them.
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

  defp visit_page(options) do
    fixture = HTTPFixtures.register(fn _request -> %{body: "<p>Common room</p>"} end)
    session = :playwright |> start_session(options) |> visit(HTTPFixtures.path(fixture, "/common-room"))
    request = fixture |> HTTPFixtures.requests() |> Enum.find(&(&1.path == "/common-room"))
    {session, request.headers}
  end
end
