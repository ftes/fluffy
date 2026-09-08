defmodule Fluffy.Conformance.StaticHTTPLinkTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "resolves a relative link against the current document with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<a href="next?state=open#details">Next order</a>))},
          %{body: html("<h1>Next order page</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/orders/current"))
      |> click(by_role(:link, name: "Next order"))
      |> expect(visible(by_text("Next order page")))
      |> expect(Page.to_have_url(TestHTTPFixtures.url(fixture, "/orders/next?state=open#details")))

      assert Enum.map(TestHTTPFixtures.requests(fixture), &{&1.path, &1.query}) == [
               {"/orders/current", ""},
               {"/orders/next", "state=open"}
             ]
    end

    @tag driver: driver
    test "follows an absolute same-origin link with #{driver}", %{driver: driver} do
      destination = Fluffy.TestServer.base_url() <> "/chamber"

      fixture =
        TestHTTPFixtures.register(%{
          body: html(~s(<a href="#{destination}">Absolute destination</a>))
        })

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/absolute"))
      |> click(by_role(:link, name: "Absolute destination"))
      |> expect(visible(by_text("The guardian sleeps")))
      |> expect(Page.to_have_url(destination))
    end

    @tag driver: driver
    test "a fragment-only link changes the URL without another request with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register(%{
          body: html(~s(<a href="#details">Details</a><h2 id="details">Order details</h2>))
        })

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/orders/current?state=open"))
      |> click(by_role(:link, name: "Details"))
      |> expect(visible(by_text("Order details")))
      |> expect(Page.to_have_url(TestHTTPFixtures.url(fixture, "/orders/current?state=open#details")))

      assert [_request] = TestHTTPFixtures.requests(fixture)
    end
  end

  test "Phoenix rejects external link navigation explicitly" do
    fixture =
      TestHTTPFixtures.register(%{
        body: html(~s(<a href="https://example.com/orders">External</a>))
      })

    session = start_test_session(:phoenix)

    session = visit(session, TestHTTPFixtures.path(fixture, "/source"))

    assert_raise Fluffy.CapabilityError, ~r/external_navigation/, fn ->
      click(session, by_role(:link, name: "External"))
    end
  end

  test "a Phoenix session reclassifies a linked LiveView destination" do
    fixture =
      TestHTTPFixtures.register(%{
        body: html(~s(<a href="/live/three-heads" target="_blank">Open counter</a>))
      })

    session = start_test_session(:phoenix)
    session = visit(session, TestHTTPFixtures.path(fixture, "/source"))

    assert Session.current_driver(session) == :static

    session = click(session, by_role(:link, name: "Open counter"))

    assert Session.current_driver(session) == :live
    expect(session, visible(by_text("Sleeping heads: 0")))
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body) do
    "<!doctype html><html><body><main>#{body}</main></body></html>"
  end
end
