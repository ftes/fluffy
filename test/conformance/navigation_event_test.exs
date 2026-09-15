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
        |> expect(Fluffy.Expect.navigation_to_have_from_url(:continue, from_url))
        |> expect(Fluffy.Expect.navigation_to_have_url(:continue, destination))
        |> expect(Fluffy.Expect.navigation_to_have_status(:continue, 202))
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
      |> expect(Fluffy.Expect.navigation_to_have_url(:submit, destination))
      |> expect(Fluffy.Expect.navigation_to_have_status(:submit, 201))
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
      |> expect(Fluffy.Expect.navigation_to_have_url(:redirect, destination))
      |> expect(Fluffy.Expect.navigation_to_have_status(:redirect, 203))
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

  for driver <- [:phoenix, :playwright], redirect? <- [false, true] do
    @tag driver: driver
    test "captures the first navigation and retains the current page with #{driver}, redirect: #{redirect?}", %{
      driver: driver
    } do
      first_path = if unquote(redirect?), do: "redirect", else: "first"

      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" -> %{body: html(~s(<a href="#{first_path}">First</a>))}
            "/redirect" -> %{status: 302, headers: [{"location", "first"}], body: ""}
            "/first" -> %{status: 201, body: html(~s(<a href="second">Second</a>))}
            "/second" -> %{status: 202, body: html("<h1>Second document</h1>")}
          end
        end)

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.navigation(:first), fn session ->
        session |> click(by_role(:link, name: "First")) |> click(by_role(:link, name: "Second"))
      end)
      |> expect(navigation_to_have_from_url(:first, TestHTTPFixtures.url(fixture, "/start")))
      |> expect(navigation_to_have_url(:first, TestHTTPFixtures.url(fixture, "/first")))
      |> expect(navigation_to_have_status(:first, 201))
      |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/second")))
      |> expect(page_to_have_status(202))
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "retains a fragment navigation before a new document with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" ->
              %{
                body:
                  html(~s(<a href="#section">Section</a><a href="second">Second</a><p id="section">Section content</p>))
              }

            "/second" ->
              %{status: 202, body: html("<h1>Second document</h1>")}
          end
        end)

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.navigation(:first), fn session ->
        session |> click(by_role(:link, name: "Section", exact: true)) |> click(by_role(:link, name: "Second"))
      end)
      |> expect(navigation_to_have_from_url(:first, TestHTTPFixtures.url(fixture, "/start")))
      |> expect(navigation_to_have_url(:first, TestHTTPFixtures.url(fixture, "/start#section")))
      |> expect(navigation_to_have_status(:first, 200))
      |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/second")))
      |> expect(page_to_have_status(202))
    end

    @tag driver: driver
    test "does not capture navigation when the action leaves the page unchanged with #{driver}", %{driver: driver} do
      session = driver |> start_test_session() |> visit("/chamber")

      assert_raise ExUnit.AssertionError, ~r/no matching event occurred/, fn ->
        wait_for(session, Event.navigation(:missing, timeout: 100), & &1)
      end
    end
  end

  for driver <- [:phoenix, :playwright], kind <- [:patch, :navigate] do
    @tag driver: driver
    test "retains a LiveView #{kind} before another navigation with #{driver}", %{driver: driver} do
      {link, destination} =
        case unquote(kind) do
          :patch -> {"Reveal passage", "/live/chamber-map?step=patched"}
          :navigate -> {"Secret chamber", "/live/secret-chamber"}
        end

      driver
      |> start_test_session()
      |> visit("/live/chamber-map")
      |> wait_for(Event.navigation(:first), fn session ->
        session
        |> click(by_role(:link, name: link, exact: true))
        |> expect(page_to_have_url(destination))
        |> visit("/chamber")
      end)
      |> expect(navigation_to_have_from_url(:first, Fluffy.TestServer.base_url() <> "/live/chamber-map"))
      |> expect(navigation_to_have_url(:first, Fluffy.TestServer.base_url() <> destination))
      |> expect(navigation_to_have_status(:first, 200))
      |> expect(page_to_have_url("/chamber"))
      |> expect(page_to_have_status(200))
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "captures a same-URL reload before another navigation with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/chamber")
      |> wait_for(Event.navigation(:first), fn session ->
        session |> reload() |> visit("/live/chamber-map")
      end)
      |> expect(navigation_to_have_from_url(:first, Fluffy.TestServer.base_url() <> "/chamber"))
      |> expect(navigation_to_have_url(:first, Fluffy.TestServer.base_url() <> "/chamber"))
      |> expect(navigation_to_have_status(:first, 200))
      |> expect(page_to_have_url("/live/chamber-map"))
    end

    @tag driver: driver
    test "ignores a LiveView patch to the current URL with #{driver}", %{driver: driver} do
      session = driver |> start_test_session() |> visit("/live/chamber-map?step=patched")

      assert_raise ExUnit.AssertionError, ~r/no matching event occurred/, fn ->
        wait_for(
          session,
          Event.navigation(:unchanged, timeout: 500),
          &click(&1, by_role(:link, name: "Reveal passage", exact: true))
        )
      end
    end
  end
end
