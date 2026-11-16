defmodule Fluffy.Conformance.StaticHTTPErrorTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.HTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "renders an HTTP error response as a page with #{driver}", %{driver: driver} do
      fixture =
        HTTPFixtures.register(%{
          status: 404,
          body: "<!doctype html><html><body><h1>Owl not found</h1></body></html>"
        })

      session = start_test_session(driver)

      session
      |> visit(HTTPFixtures.path(fixture, "/missing"))
      |> expect("Owl not found" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(HTTPFixtures.url(fixture, "/missing")))
    end

    @tag driver: driver
    test "renders a redirect status without Location as a page with #{driver}", %{driver: driver} do
      fixture =
        HTTPFixtures.register(%{
          status: 302,
          body: "<!doctype html><html><body><h1>No redirect target</h1></body></html>"
        })

      session = start_test_session(driver)

      session
      |> visit(HTTPFixtures.path(fixture, "/no-location"))
      |> expect("No redirect target" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(HTTPFixtures.url(fixture, "/no-location")))
    end
  end

  test "Phoenix reports an unsupported navigation scheme precisely" do
    session = start_test_session(:phoenix)

    assert_raise Fluffy.CapabilityError, ~r/navigation_scheme.*mailto/s, fn ->
      visit(session, "mailto:owlery@hogwarts.example")
    end
  end

  test "Phoenix reports a same-scheme cross-origin navigation precisely" do
    session = start_test_session(:phoenix)

    assert_raise Fluffy.CapabilityError, ~r/external_navigation/, fn ->
      visit(session, "http://hogwarts.example/owls")
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.Support.Server.base_url(),
      endpoint: Fluffy.Support.Web.Endpoint
    )
  end
end
