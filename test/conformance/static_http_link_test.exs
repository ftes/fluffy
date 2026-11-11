defmodule Fluffy.Conformance.StaticHTTPLinkTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Session
  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "resolves a relative link against the current document with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<a href="next?state=open#details">Next owl</a>))},
          %{body: html("<h1>Next owl landed</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/owls/current"))
      |> click(by_role(:link, name: "Next owl"))
      |> expect("Next owl landed" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/owls/next?state=open#details")))

      assert Enum.map(TestHTTPFixtures.requests(fixture), &{&1.path, &1.query}) == [
               {"/owls/current", ""},
               {"/owls/next", "state=open"}
             ]
    end

    @tag driver: driver
    test "a click on text inside a link follows the link with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<a href="next"><span>Next owl</span></a>))},
          %{body: html("<h1>Next owl landed</h1>")}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/owls/current"))
      |> click(by_text("Next owl", exact: true))
      |> expect("Next owl landed" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/owls/next")))
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
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(destination))
    end

    @tag driver: driver
    test "a fragment-only link changes the URL without another request with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register(%{
          body: html(~s(<a href="#details">Details</a><h2 id="details">Owl details</h2>))
        })

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/owls/current?state=open"))
      |> click(by_role(:link, name: "Details"))
      |> expect("Owl details" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/owls/current?state=open#details")))

      assert [_request] = TestHTTPFixtures.requests(fixture)
    end

    for status <- [204, 205] do
      @tag driver: driver
      test "a link to a #{status} response keeps the current page with #{driver}", %{driver: driver} do
        fixture =
          TestHTTPFixtures.register_sequence([
            %{body: html(~s(<h1>Current owl</h1><a href="sign">Sign for parcel</a>))},
            %{status: unquote(status)}
          ])

        driver
        |> start_test_session()
        |> visit(TestHTTPFixtures.path(fixture, "/owls/current"))
        |> click(by_role(:link, name: "Sign for parcel"))
        |> expect("Current owl" |> by_text() |> to_be_visible())
        |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/owls/current")))

        assert Enum.map(TestHTTPFixtures.requests(fixture), & &1.path) == ["/owls/current", "/owls/sign"]
      end
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
    expect(session, "Sleeping heads: 0" |> by_text() |> to_be_visible())
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
