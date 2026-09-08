defmodule Fluffy.Conformance.StaticHTTPErrorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Page
  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "renders an HTTP error response as a page with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(%{
          status: 404,
          body: "<!doctype html><html><body><h1>Order not found</h1></body></html>"
        })

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/missing"))
      |> expect(Page.to_have_status(404))
      |> expect(visible(by_text("Order not found")))
      |> expect(Page.to_have_url(TestHTTPFixtures.url(fixture, "/missing")))
    end

    @tag driver: driver
    test "renders a redirect status without Location as a page with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(%{
          status: 302,
          body: "<!doctype html><html><body><h1>No redirect target</h1></body></html>"
        })

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/no-location"))
      |> expect(Page.to_have_status(302))
      |> expect(visible(by_text("No redirect target")))
      |> expect(Page.to_have_url(TestHTTPFixtures.url(fixture, "/no-location")))
    end
  end

  test "Phoenix reports an unsupported navigation scheme precisely" do
    session = start_test_session(:phoenix)

    assert_raise Fluffy.CapabilityError, ~r/navigation_scheme.*mailto/s, fn ->
      visit(session, "mailto:orders@example.com")
    end
  end

  test "Phoenix reports a same-scheme cross-origin navigation precisely" do
    session = start_test_session(:phoenix)

    assert_raise Fluffy.CapabilityError, ~r/external_navigation/, fn ->
      visit(session, "http://example.com/orders")
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
