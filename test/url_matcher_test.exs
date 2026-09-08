defmodule Fluffy.URLMatcherTest do
  use ExUnit.Case, async: true

  alias Fluffy.URLMatcher

  test "a path-only matcher ignores query and fragment" do
    matcher = URLMatcher.new!(path: "/accounts")

    assert URLMatcher.matches?(matcher, "https://example.test/accounts?tenant=shire#members")
    refute URLMatcher.matches?(matcher, "https://example.test/account")
  end

  test "exact query matching ignores distinct-name order and retains repeated-value order" do
    matcher =
      URLMatcher.new!(
        path: "/accounts",
        query: %{"empty" => "", "id" => "5", "tag" => ["a", "b", "b"]}
      )

    assert URLMatcher.matches?(matcher, "https://example.test/accounts?tag=a&id=5&empty&tag=b&tag=b")
    assert URLMatcher.matches?(matcher, "https://example.test/accounts?id=5&tag=a&empty=&tag=b&tag=b")

    refute URLMatcher.matches?(matcher, "https://example.test/accounts?id=5&tag=b&tag=a&tag=b&empty=")
    refute URLMatcher.matches?(matcher, "https://example.test/accounts?id=5&tag=a&tag=b&empty=")
    refute URLMatcher.matches?(matcher, "https://example.test/accounts?id=5&tag=a&tag=b&tag=b&empty=&extra=1")
  end

  test "subset mode allows unrelated names but still requires the complete ordered value list for each named parameter" do
    matcher =
      URLMatcher.new!(
        query: %{"id" => "5", "tag" => ["a", "b"]},
        query_mode: :subset
      )

    assert URLMatcher.matches?(matcher, "https://example.test/accounts?tag=a&other=1&id=5&tag=b")
    refute URLMatcher.matches?(matcher, "https://example.test/accounts?tag=a&id=5&tag=b&tag=c")
    refute URLMatcher.matches?(matcher, "https://example.test/accounts?tag=a&tag=b")
  end

  test "query parsing follows URLSearchParams for empty values, plus signs, spaces, and Unicode" do
    matcher =
      URLMatcher.new!(
        query: %{
          "bare" => "",
          "empty" => "",
          "plus" => "+",
          "space" => "hello world",
          "unicode" => "ä"
        }
      )

    assert URLMatcher.matches?(
             matcher,
             "https://example.test/?space=hello+world&empty=&bare&plus=%2B&unicode=%C3%A4"
           )

    assert URLMatcher.matches?(
             matcher,
             "https://example.test/?space=hello%20world&empty&bare=&plus=%2b&unicode=%c3%a4"
           )

    refute URLMatcher.matches?(matcher, "https://example.test/?space=hello+world&plus=%2B&unicode=%C3%A4")
  end

  test "an explicit fragment distinguishes missing, empty, and present fragments" do
    assert URLMatcher.matches?(URLMatcher.new!(fragment: "summary"), "https://example.test/#summary")
    refute URLMatcher.matches?(URLMatcher.new!(fragment: nil), "https://example.test/#summary")
    assert URLMatcher.matches?(URLMatcher.new!(fragment: nil), "https://example.test/")
  end

  test "an exact empty query distinguishes no parameters from any parameter" do
    matcher = URLMatcher.new!(query: %{})

    assert URLMatcher.matches?(matcher, "https://example.test/accounts")
    assert URLMatcher.matches?(matcher, "https://example.test/accounts?")
    refute URLMatcher.matches?(matcher, "https://example.test/accounts?empty")
  end

  test "structured matcher validation rejects ambiguous or lossy input" do
    assert_raise NimbleOptions.ValidationError, fn -> URLMatcher.new!([]) end
    assert_raise NimbleOptions.ValidationError, fn -> URLMatcher.new!(query_mode: :subset) end
    assert_raise NimbleOptions.ValidationError, fn -> URLMatcher.new!(query: %{id: "5"}) end
    assert_raise NimbleOptions.ValidationError, fn -> URLMatcher.new!(query: %{"tag" => ["a", 2]}) end
  end
end
