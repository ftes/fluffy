defmodule Fluffy.Conformance.PageURLTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect

  alias Fluffy.TestWeb.Endpoint

  @query "b=2&a=1&tag=a&tag=b&empty=&bare&space=hello+world&unicode=%C3%A4&plus=%2B"

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "immediate URL assertions read the current URL and report mismatches with #{driver}", %{driver: driver} do
      session =
        driver
        |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
        |> visit("/chamber")
        |> expect(page_to_have_url(path: "/chamber"), timeout: 0)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          expect(session, page_to_have_url(path: "/missing"), timeout: 0)
        end

      assert error.message =~ "/chamber"
      expect(session, not_(page_to_have_url(path: "/missing")), timeout: 0)
    end

    @tag driver: driver
    test "matches structured URLs on a Static document with #{driver}", %{driver: driver} do
      driver
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/chamber?#{@query}#summary")
      |> expect(Fluffy.Expect.page_to_have_url(path: "/chamber"))
      |> expect(
        Fluffy.Expect.page_to_have_url(
          path: "/chamber",
          query: %{
            "a" => "1",
            "b" => "2",
            "bare" => "",
            "empty" => "",
            "plus" => "+",
            "space" => "hello world",
            "tag" => ["a", "b"],
            "unicode" => "ä"
          },
          fragment: "summary"
        )
      )
      |> expect(
        Fluffy.Expect.page_to_have_url(
          path: "/chamber",
          query: %{"space" => "hello world", "tag" => ["a", "b"]},
          query_mode: :subset
        )
      )
      |> expect(not_(Fluffy.Expect.page_to_have_url(query: %{"tag" => ["b", "a"]}, query_mode: :subset)))
      |> expect(not_(Fluffy.Expect.page_to_have_url(fragment: nil)))
    end

    @tag driver: driver
    test "preserves exact string and regular-expression URL semantics with #{driver}", %{driver: driver} do
      exact = Fluffy.TestServer.base_url() <> "/chamber?#{@query}#summary"

      driver
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/chamber?#{@query}#summary")
      |> expect(Fluffy.Expect.page_to_have_url(exact))
      |> expect(Fluffy.Expect.page_to_have_url(~r{/chamber\?b=2&a=1&tag=a&tag=b&}))
      |> expect(not_(Fluffy.Expect.page_to_have_url("/chamber?a=1&b=2")))
    end

    @tag driver: driver
    test "matches the same structured URL on a Live document with #{driver}", %{driver: driver} do
      driver
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/live/chamber-map?b=2&a=1&tag=a&tag=b#summary")
      |> expect(
        Fluffy.Expect.page_to_have_url(
          path: "/live/chamber-map",
          query: %{"a" => "1", "b" => "2", "tag" => ["a", "b"]},
          fragment: "summary"
        )
      )
    end
  end

  for driver <- [:phoenix, :playwright], path <- ["/chamber", "/live/chamber-map"] do
    @tag driver: driver
    test "URI predicates and negation work on #{path} with #{driver}", %{driver: driver} do
      path = unquote(path)

      session =
        driver
        |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
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
  test "waits for a future same-document URL change with a URI predicate" do
    session = session_for_html(:playwright, "<h1>URL changes</h1>")
    Fluffy.Playwright.evaluate(session, "setTimeout(() => location.hash = 'ready', 100)")
    expect(session, page_to_have_url(&(&1.fragment == "ready")), timeout: 1_000)
    Fluffy.Playwright.evaluate(session, "setTimeout(() => location.hash = 'finished', 100)")
    expect(session, not_(page_to_have_url(&(&1.fragment == "ready"))), timeout: 1_000)
  end
end
