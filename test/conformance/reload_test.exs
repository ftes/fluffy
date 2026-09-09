defmodule Fluffy.Conformance.ReloadTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "reloads the current document and preserves the URL with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html("<h1>First render</h1>")},
          %{body: html("<h1>Second render</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture))
      |> expect("First render" |> by_text() |> to_be_visible())
      |> reload()
      |> expect("Second render" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture)))

      assert length(TestHTTPFixtures.requests(fixture)) == 2
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end
