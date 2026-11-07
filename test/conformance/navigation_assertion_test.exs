defmodule Fluffy.Conformance.NavigationAssertionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "asserts link navigation URL and content with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" -> %{body: html(~s(<a href="destination?source=link">Continue</a>))}
            "/destination" -> %{body: html("<h1>Arrived</h1>")}
          end
        end)

      destination = TestHTTPFixtures.url(fixture, "/destination?source=link")
      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> click(by_role(:link, name: "Continue"))
      |> expect(page_to_have_url(destination))
      |> expect("Arrived" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "asserts form submission navigation with #{driver}", %{driver: driver} do
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
              %{body: html("<h1>Submitted</h1>")}
          end
        end)

      destination = TestHTTPFixtures.url(fixture, "/submit")
      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> fill(by_label("Query"), "fluffy")
      |> click(by_role(:button, name: "Search"))
      |> expect(page_to_have_url(destination))
      |> expect("Submitted" |> by_text() |> to_be_visible())

      [request] =
        fixture
        |> TestHTTPFixtures.requests()
        |> Enum.filter(&(&1.path == "/submit"))

      assert request.method == "POST"
      assert request.body == "query=fluffy&intent=search"
    end

    @tag driver: driver
    test "asserts the final document after a redirect with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" -> %{body: html(~s(<a href="redirect">Continue</a>))}
            "/redirect" -> %{status: 302, headers: [{"location", "final"}], body: ""}
            "/final" -> %{body: html("<h1>Final</h1>")}
          end
        end)

      destination = TestHTTPFixtures.url(fixture, "/final")
      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> click(by_role(:link, name: "Continue"))
      |> expect(page_to_have_url(destination))
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
    test "asserts sequential navigations with #{driver}, redirect: #{redirect?}", %{
      driver: driver
    } do
      first_path = if unquote(redirect?), do: "redirect", else: "first"

      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" -> %{body: html(~s(<a href="#{first_path}">First</a>))}
            "/redirect" -> %{status: 302, headers: [{"location", "first"}], body: ""}
            "/first" -> %{body: html(~s(<a href="second">Second</a>))}
            "/second" -> %{body: html("<h1>Second document</h1>")}
          end
        end)

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> click(by_role(:link, name: "First"))
      |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/first")))
      |> expect(:link |> by_role(name: "First") |> to_have_count(0))
      |> click(by_role(:link, name: "Second"))
      |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/second")))
      |> expect(:heading |> by_role(name: "Second document") |> to_be_visible())
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "asserts a fragment navigation before a new document with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" ->
              %{
                body:
                  html(~s(<a href="#section">Section</a><a href="second">Second</a><p id="section">Section content</p>))
              }

            "/second" ->
              %{body: html("<h1>Second document</h1>")}
          end
        end)

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> click(by_role(:link, name: "Section", exact: true))
      |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/start#section")))
      |> expect("Section content" |> by_text() |> to_be_visible())
      |> click(by_role(:link, name: "Second"))
      |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/second")))
      |> expect(:heading |> by_role(name: "Second document") |> to_be_visible())
    end
  end

  for driver <- [:phoenix, :playwright], kind <- [:patch, :navigate] do
    @tag driver: driver
    test "asserts a LiveView #{kind} before another navigation with #{driver}", %{driver: driver} do
      {link, destination, content} =
        case unquote(kind) do
          :patch -> {"Reveal passage", "/live/chamber-map?step=patched", "Map position: patched"}
          :navigate -> {"Secret chamber", "/live/secret-chamber", "The secret chamber is open"}
        end

      driver
      |> start_test_session()
      |> visit("/live/chamber-map")
      |> click(by_role(:link, name: link, exact: true))
      |> expect(page_to_have_url(destination))
      |> expect(content |> by_text(exact: true) |> to_be_visible())
      |> visit("/chamber")
      |> expect(page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "asserts a same-URL reload before another navigation with #{driver}", %{driver: driver} do
      driver
      |> start_test_session()
      |> visit("/chamber")
      |> reload()
      |> expect(page_to_have_url("/chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> visit("/live/chamber-map")
      |> expect(page_to_have_url("/live/chamber-map"))
    end

    @tag driver: driver
    test "keeps the URL after a LiveView patch to the current URL with #{driver}", %{driver: driver} do
      session = driver |> start_test_session() |> visit("/live/chamber-map?step=patched")

      session
      |> click(by_role(:link, name: "Reveal passage", exact: true))
      |> expect(page_to_have_url("/live/chamber-map?step=patched"))
    end
  end
end
