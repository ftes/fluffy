defmodule Fluffy.PlaywrightURLOracleTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Playwright
  alias Fluffy.TestWeb.Endpoint

  @tag driver: :playwright
  test "pins WHATWG URL component and URLSearchParams normalization" do
    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
      |> visit(
        "/chamber?tag=a&other=1&tag=b&bare&empty=&space=hello+world&encoded=hello%20world&plus=%2B&unicode=%C3%A4#summary"
      )

    assert %{
             "hash" => "#summary",
             "pathname" => "/chamber",
             "search" =>
               "?tag=a&other=1&tag=b&bare&empty=&space=hello+world&encoded=hello%20world&plus=%2B&unicode=%C3%A4",
             "values" => %{
               "bare" => [""],
               "empty" => [""],
               "encoded" => ["hello world"],
               "plus" => ["+"],
               "space" => ["hello world"],
               "tag" => ["a", "b"],
               "unicode" => ["ä"]
             }
           } ==
             Playwright.evaluate(
               session,
               """
               () => {
                 const url = new URL(location.href)
                 const names = ["bare", "empty", "encoded", "plus", "space", "tag", "unicode"]
                 return {
                   pathname: url.pathname,
                   search: url.search,
                   hash: url.hash,
                   values: Object.fromEntries(names.map(name => [name, url.searchParams.getAll(name)]))
                 }
               }
               """,
               is_function: true
             )
  end
end
