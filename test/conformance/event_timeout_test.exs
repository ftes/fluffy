defmodule Fluffy.Conformance.EventTimeoutTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.TestHTTPFixtures

  setup do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body: """
              <!doctype html><html><body>
              <a href="destination">Continue</a>
              <a href="noise">Noise</a>
              <a href="report">Download</a>
              </body></html>
              """
            }

          "/destination" ->
            %{status: 201, body: "<!doctype html><html><body>Arrived</body></html>"}

          path ->
            filename = if path == "/noise", do: "noise.txt", else: "report.csv"

            %{
              headers: [{"content-disposition", "attachment; filename=#{filename}"}],
              body: "download bytes"
            }
        end
      end)

    %{fixture: fixture}
  end

  for driver <- [:phoenix, :playwright], timeout <- [0, 100] do
    @tag driver: driver
    test "ignores navigation after a #{timeout} ms deadline with #{driver}", %{driver: driver, fixture: fixture} do
      session = start_test_session(driver, fixture)

      assert_raise ExUnit.AssertionError, ~r/no matching event occurred/, fn ->
        wait_for(session, Event.navigation(:late, timeout: unquote(timeout)), fn session ->
          Process.sleep(unquote(timeout))

          session
          |> click(by_role(:link, name: "Continue"))
          |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/destination")))
        end)
      end
    end

    @tag driver: driver
    test "ignores matching downloads after a #{timeout} ms deadline with #{driver}", %{
      driver: driver,
      fixture: fixture
    } do
      session = start_test_session(driver, fixture)

      assert_raise ExUnit.AssertionError, ~r/no matching event occurred/, fn ->
        wait_for(
          session,
          Event.download(:late,
            filename: "report.csv",
            url: TestHTTPFixtures.url(fixture, "/report"),
            max_bytes: 1,
            timeout: unquote(timeout)
          ),
          fn session ->
            Process.sleep(unquote(timeout))
            click(session, by_role(:link, name: "Download"))
          end
        )
      end
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "retains navigation captured before the deadline when the callback finishes later with #{driver}", %{
      driver: driver,
      fixture: fixture
    } do
      driver
      |> start_test_session(fixture)
      |> wait_for(Event.navigation(:early, timeout: 1_000), fn session ->
        session = click(session, by_role(:link, name: "Continue"))
        Process.sleep(1_000)
        session
      end)
      |> expect(navigation_to_have_url(:early, TestHTTPFixtures.url(fixture, "/destination")))
      |> expect(navigation_to_have_status(:early, 201))
    end

    @tag driver: driver
    test "a rejected download does not restart the deadline with #{driver}", %{driver: driver, fixture: fixture} do
      session = start_test_session(driver, fixture)

      assert_raise ExUnit.AssertionError, ~r/no matching event occurred/, fn ->
        wait_for(session, Event.download(:late, filename: "report.csv", timeout: 1_000), fn session ->
          Process.sleep(600)
          session = click(session, by_role(:link, name: "Noise"))
          Process.sleep(600)
          click(session, by_role(:link, name: "Download"))
        end)
      end
    end
  end

  defp start_test_session(driver, fixture) do
    driver
    |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
    |> visit(TestHTTPFixtures.path(fixture, "/start"))
  end
end
