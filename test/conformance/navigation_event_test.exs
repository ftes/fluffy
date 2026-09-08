defmodule Fluffy.Conformance.NavigationEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.NavigationEvent
  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "captures link navigation metadata with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" -> %{body: html(~s(<a href="destination?source=link">Continue</a>))}
            "/destination" -> %{status: 202, body: html("<h1>Arrived</h1>")}
          end
        end)

      from_url = TestHTTPFixtures.url(fixture, "/start")
      destination = TestHTTPFixtures.url(fixture, "/destination?source=link")
      session = start_test_session(driver)

      session =
        session
        |> visit(TestHTTPFixtures.path(fixture, "/start"))
        |> wait_for(Event.navigation(:continue), &click(&1, by_role(:link, name: "Continue")))
        |> expect(to_have_navigation_from_url(:continue, from_url))
        |> expect(to_have_navigation_url(:continue, destination))
        |> expect(to_have_navigation_status(:continue, 202))
        |> expect("Arrived" |> by_text() |> to_be_visible())

      assert %NavigationEvent{url: ^destination, status: 202} =
               navigation(session, :continue)
    end

    @tag driver: driver
    test "captures form submission navigation with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" ->
              %{
                body:
                  html("""
                  <form action="submit" method="post">
                    <label>Query <input name="query"></label>
                    <button name="intent" value="search">Search</button>
                  </form>
                  """)
              }

            "/submit" ->
              %{status: 201, body: html("<h1>Submitted</h1>")}
          end
        end)

      destination = TestHTTPFixtures.url(fixture, "/submit")
      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> fill(by_label("Query"), "fluffy")
      |> wait_for(Event.navigation(:submit), &click(&1, by_role(:button, name: "Search")))
      |> expect(to_have_navigation_url(:submit, destination))
      |> expect(to_have_navigation_status(:submit, 201))
      |> expect("Submitted" |> by_text() |> to_be_visible())

      [request] =
        fixture
        |> TestHTTPFixtures.requests()
        |> Enum.filter(&(&1.path == "/submit"))

      assert request.method == "POST"
      assert request.body == "query=fluffy&intent=search"
    end

    @tag driver: driver
    test "captures the final response after a redirect with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" -> %{body: html(~s(<a href="redirect">Continue</a>))}
            "/redirect" -> %{status: 302, headers: [{"location", "final"}], body: ""}
            "/final" -> %{status: 203, body: html("<h1>Final</h1>")}
          end
        end)

      destination = TestHTTPFixtures.url(fixture, "/final")
      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.navigation(:redirect), &click(&1, by_role(:link, name: "Continue")))
      |> expect(to_have_navigation_url(:redirect, destination))
      |> expect(to_have_navigation_status(:redirect, 203))
      |> expect("Final" |> by_text() |> to_be_visible())
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
