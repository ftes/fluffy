defmodule Fluffy.Conformance.EventTimeoutTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Support.HTTPFixtures

  setup do
    fixture =
      HTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body: """
              <!doctype html><html><body>
              <a href="destination">Continue</a>
              <a href="noise">Noise</a>
              <a href="marauders-map">Download</a>
              </body></html>
              """
            }

          "/destination" ->
            %{status: 201, body: "<!doctype html><html><body>Arrived</body></html>"}

          path ->
            filename = if path == "/noise", do: "noise.txt", else: "marauders_map.csv"

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
    test "ignores matching downloads after a #{timeout} ms deadline with #{driver}", %{
      driver: driver,
      fixture: fixture
    } do
      session = start_test_session(driver, fixture)

      assert_raise ExUnit.AssertionError, ~r/no matching download event/, fn ->
        expect_event(
          session,
          Event.download(&(&1.suggested_filename == "marauders_map.csv")),
          fn session ->
            Process.sleep(unquote(timeout))
            click(session, by_role(:link, name: "Download"))
          end,
          timeout: unquote(timeout)
        )
      end
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "retains a download captured before the deadline when the callback finishes later with #{driver}", %{
      driver: driver,
      fixture: fixture
    } do
      # The deadline leaves room for a browser click under parallel cases
      # (Firefox dispatches input for one page at a time); the callback still
      # outlives it.
      driver
      |> start_test_session(fixture)
      |> expect_event(
        Event.download(&(&1.suggested_filename == "marauders_map.csv")),
        fn session ->
          click(session, by_role(:link, name: "Download"))
          Process.sleep(3_000)
        end,
        fn download ->
          assert download.suggested_filename == "marauders_map.csv"
          assert Fluffy.Download.read(download) == "download bytes"
          assert download.url == HTTPFixtures.url(fixture, "/marauders-map")
        end,
        timeout: 3_000
      )
      |> expect(page_to_have_url(HTTPFixtures.url(fixture, "/start")))
    end

    @tag driver: driver
    test "a rejected download does not restart the deadline with #{driver}", %{driver: driver, fixture: fixture} do
      session = start_test_session(driver, fixture)

      assert_raise ExUnit.AssertionError, ~r/no matching download event/, fn ->
        expect_event(
          session,
          Event.download(&(&1.suggested_filename == "marauders_map.csv")),
          fn session ->
            Process.sleep(600)
            session = click(session, by_role(:link, name: "Noise"))
            Process.sleep(600)
            click(session, by_role(:link, name: "Download"))
          end,
          timeout: 1_000
        )
      end
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "timeout: :infinity waits for the event with #{driver}", %{driver: driver, fixture: fixture} do
      driver
      |> start_test_session(fixture)
      |> expect_event(
        Event.download(&(&1.suggested_filename == "marauders_map.csv")),
        fn session ->
          Process.sleep(150)
          click(session, by_role(:link, name: "Download"), timeout: 5_000)
        end,
        &assert(&1.suggested_filename == "marauders_map.csv"),
        timeout: :infinity
      )
    end
  end

  defp start_test_session(driver, fixture) do
    driver
    |> start_session(base_url: Fluffy.Support.Server.base_url(), endpoint: Fluffy.Support.Web.Endpoint)
    |> visit(HTTPFixtures.path(fixture, "/start"))
  end
end
