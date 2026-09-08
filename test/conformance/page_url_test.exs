defmodule Fluffy.Conformance.PageURLTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Page
  alias Fluffy.TestWeb.Endpoint

  @query "b=2&a=1&tag=a&tag=b&empty=&bare&space=hello+world&unicode=%C3%A4&plus=%2B"

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "matches structured URLs on a Static document with #{driver}", %{driver: driver} do
      driver
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/chamber?#{@query}#summary")
      |> expect(Page.to_have_url(path: "/chamber"))
      |> expect(
        Page.to_have_url(
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
        Page.to_have_url(
          path: "/chamber",
          query: %{"space" => "hello world", "tag" => ["a", "b"]},
          query_mode: :subset
        )
      )
      |> expect(not_(Page.to_have_url(query: %{"tag" => ["b", "a"]}, query_mode: :subset)))
      |> expect(not_(Page.to_have_url(fragment: nil)))
    end

    @tag driver: driver
    test "preserves exact string and regular-expression URL semantics with #{driver}", %{driver: driver} do
      exact = Fluffy.TestServer.base_url() <> "/chamber?#{@query}#summary"

      driver
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/chamber?#{@query}#summary")
      |> expect(Page.to_have_url(exact))
      |> expect(Page.to_have_url(~r{/chamber\?b=2&a=1&tag=a&tag=b&}))
      |> expect(not_(Page.to_have_url("/chamber?a=1&b=2")))
    end

    @tag driver: driver
    test "matches the same structured URL on a Live document with #{driver}", %{driver: driver} do
      driver
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit("/live/chamber-map?b=2&a=1&tag=a&tag=b#summary")
      |> expect(
        Page.to_have_url(
          path: "/live/chamber-map",
          query: %{"a" => "1", "b" => "2", "tag" => ["a", "b"]},
          fragment: "summary"
        )
      )
    end
  end
end
