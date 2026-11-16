defmodule Fluffy.Conformance.PageURLTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect

  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  @query "b=2&a=1&tag=a&tag=b&empty=&bare&space=hello+world&unicode=%C3%A4&plus=%2B"

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "immediate URL assertions read the current URL and report mismatches with #{driver}", %{driver: driver} do
      session =
        driver
        |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
        |> visit("/chamber")
        |> expect(page_to_have_url("/chamber"), timeout: 0)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          expect(session, page_to_have_url("/missing"), timeout: 0)
        end

      assert error.message =~ "/chamber"
      expect(session, not_(page_to_have_url("/missing")), timeout: 0)
    end

    @tag driver: driver
    test "a string is resolved against the base URL and equals the complete URL with #{driver}", %{driver: driver} do
      exact = Server.base_url() <> "/chamber?#{@query}#summary"

      driver
      |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
      |> visit("/chamber?#{@query}#summary")
      |> expect(Fluffy.Expect.page_to_have_url(exact))
      |> expect(Fluffy.Expect.page_to_have_url("/chamber?#{@query}#summary"))
      |> expect(Fluffy.Expect.page_to_have_url(~r{/chamber\?b=2&a=1&tag=a&tag=b&}))
      |> expect(not_(Fluffy.Expect.page_to_have_url("/chamber")))
      |> expect(not_(Fluffy.Expect.page_to_have_url("/chamber?a=1&b=2")))
    end

    @tag driver: driver
    test "a regex is a JS RegExp, and PCRE-only syntax raises, with #{driver}", %{driver: driver} do
      session =
        driver
        |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
        |> visit("/chamber")
        |> expect(page_to_have_url(PlaywrightEx.RegExp.new("/CHAMBER$", "i")))
        |> expect(page_to_have_url(~r{/CHAMBER$}, ignore_case: true))
        |> expect(not_(page_to_have_url(~r{/CHAMBER$}i, ignore_case: false)))

      assert_raise ArgumentError, "\\z is not JS RegExp syntax: ~r/\\/chamber\\z/", fn ->
        expect(session, page_to_have_url(~r{/chamber\z}))
      end
    end

    @tag driver: driver
    test "a string matches a Live document's complete URL with #{driver}", %{driver: driver} do
      driver
      |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
      |> visit("/live/chamber-map?b=2&a=1&tag=a&tag=b#summary")
      |> expect(Fluffy.Expect.page_to_have_url("/live/chamber-map?b=2&a=1&tag=a&tag=b#summary"))
    end
  end

  for driver <- [:phoenix, :playwright], path <- ["/chamber", "/live/chamber-map"] do
    @tag driver: driver
    test "URL predicates and negation work on #{path} with #{driver}", %{driver: driver} do
      path = unquote(path)

      session =
        driver
        |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
        |> visit(path <> "?answer=42#summary")
        |> expect(
          page_to_have_url(fn %URI{path: actual, query: query, fragment: fragment} ->
            actual == path and URI.decode_query(query)["answer"] == "42" and fragment == "summary"
          end),
          timeout: 0
        )
        |> expect(not_(page_to_have_url(&(&1.path == "/missing"))), timeout: 0)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          expect(session, page_to_have_url(&(&1.path == "/missing")), timeout: 0)
        end

      assert error.message =~ path
    end
  end

  @tag driver: :playwright
  test "zero-timeout URL assertions allow the current URL predicate to finish" do
    session =
      :playwright
      |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
      |> visit("/chamber")

    predicate = fn url ->
      Process.sleep(10)
      url.path == "/chamber"
    end

    expect(session, page_to_have_url(predicate), timeout: 0)

    assert_raise ExUnit.AssertionError, fn ->
      expect(session, not_(page_to_have_url(predicate)), timeout: 0)
    end
  end

  @tag driver: :playwright
  test "waits for a future same-document URL change with a URL predicate" do
    session = session_for_html(:playwright, "<h1>URL changes</h1>")
    Fluffy.Playwright.evaluate(session, "setTimeout(() => location.hash = 'ready', 100)")
    expect(session, page_to_have_url(&(&1.fragment == "ready")), timeout: 1_000)
    Fluffy.Playwright.evaluate(session, "setTimeout(() => location.hash = 'finished', 100)")
    expect(session, not_(page_to_have_url(&(&1.fragment == "ready"))), timeout: 1_000)
  end
end
