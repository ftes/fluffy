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

  @tag driver: :playwright
  test "Playwright reload passes wait_until: through and still adopts the new document" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{body: html("<h1>First render</h1>")},
        %{body: html("<h1>Second render</h1>")}
      ])

    session = :playwright |> start_test_session() |> visit(TestHTTPFixtures.path(fixture))

    session
    |> reload(wait_until: :commit)
    |> expect("Second render" |> by_text() |> to_be_visible())

    for option <- [no_wait_after: true, signal: nil] do
      assert_raise NimbleOptions.ValidationError, fn -> reload(session, [option]) end
    end
  end

  @tag driver: :phoenix
  test "Phoenix reload raises a capability error for wait_until:" do
    fixture = TestHTTPFixtures.register_sequence([%{body: html("<h1>First render</h1>")}])
    session = :phoenix |> start_test_session() |> visit(TestHTTPFixtures.path(fixture))

    error =
      assert_raise Fluffy.CapabilityError, ~r/:wait_until is a Playwright option/, fn ->
        reload(session, wait_until: :load)
      end

    assert error.capability == :playwright_action_options
    assert length(TestHTTPFixtures.requests(fixture)) == 1
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end
