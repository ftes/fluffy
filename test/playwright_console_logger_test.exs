defmodule Fluffy.PlaywrightConsoleLoggerTest do
  use Fluffy.TestCase, async: false

  import ExUnit.CaptureLog
  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Playwright
  alias Fluffy.Playwright.ConsoleLogger
  alias Fluffy.TestHTTPFixtures

  test "formats browser messages with source locations and metadata" do
    message = %{
      method: :console,
      params: %{
        page: %{guid: "page-1"},
        location: %{url: "http://example.test/app.js", line_number: 12, column_number: 7}
      }
    }

    log = capture_log(fn -> ConsoleLogger.log(:warning, "browser warning", message) end)

    assert log =~ "browser warning (http://example.test/app.js:12:7)"
  end

  test "logs console and uncaught errors from main pages and popups" do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{body: html(~s|<button onclick="window.open('popup')">Open popup</button>|)}

          "/popup" ->
            %{body: html("<h1>Popup</h1>")}
        end
      end)

    first = start_session(:playwright, base_url: Fluffy.TestServer.base_url())
    second = start_session(:playwright, base_url: Fluffy.TestServer.base_url())

    log =
      capture_log(fn ->
        Playwright.evaluate(first, "console.error('first context error')")

        second
        |> visit(TestHTTPFixtures.path(fixture, "/start"))
        |> wait_for(Event.popup(:popup), &click(&1, by_role(:button, name: "Open popup")))
        |> switch_page(:popup)
        |> Playwright.evaluate("console.error('popup context error')")

        Playwright.evaluate(
          first,
          "setTimeout(() => { throw new Error('uncaught page failure') }, 0); 'scheduled'"
        )

        Process.sleep(25)
      end)

    assert log =~ "first context error"
    assert log =~ "popup context error"
    assert log =~ "uncaught page failure"
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end
