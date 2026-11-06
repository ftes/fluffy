defmodule Fluffy.PlaywrightConsoleLoggerTest do
  use Fluffy.TestCase, async: false

  import ExUnit.CaptureLog
  import Fluffy
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.Playwright
  alias Fluffy.TestHTTPFixtures

  test "log_browser_console: false disables browser logging" do
    config = Application.fetch_env!(:fluffy, :playwright)
    Application.put_env(:fluffy, :playwright, Keyword.put(config, :log_browser_console, false))
    on_exit(fn -> Application.put_env(:fluffy, :playwright, config) end)
    session = start_session(:playwright, base_url: Fluffy.TestServer.base_url())

    refute capture_log(fn -> Playwright.evaluate(session, "console.error('silenced error')") end) =~ "silenced error"
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
        |> then(fn session ->
          pending = wait_for(session, Event.popup())
          click(session, by_role(:button, name: "Open popup"))
          switch_page(session, await(pending))
        end)
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
