defmodule Fluffy.Conformance.DownloadEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Download
  alias Fluffy.Event
  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "captures a download before clicking and keeps the source page with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" ->
              %{
                body:
                  html("""
                  <h1>Download source</h1>
                  <a href="report">Download report</a>
                  """)
              }

            "/report" ->
              %{
                headers: [
                  {"content-disposition", "attachment; filename=orders.csv"},
                  {"content-type", "text/csv; charset=utf-8"}
                ],
                body: "id,total\n1,42\n"
              }
          end
        end)

      session = start_test_session(driver)

      session =
        session
        |> visit(TestHTTPFixtures.path(fixture, "/start"))
        |> wait_for(
          Event.download(:report, filename: "orders.csv", url: TestHTTPFixtures.url(fixture, "/report")),
          fn session ->
            click(session, by_role(:link, name: "Download report"))
          end
        )
        |> expect(Fluffy.Expect.download_to_have_suggested_filename(:report, "orders.csv"))
        |> expect(Fluffy.Expect.download_to_have_content_type(:report, "text/csv"))
        |> expect(Fluffy.Expect.download_to_have_content(:report, "id,total\n1,42\n"))
        |> expect("Download source" |> by_text() |> to_be_visible())
        |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/start")))

      assert %Download{
               filename: "orders.csv",
               content_type: "text/csv",
               bytes: "id,total\n1,42\n"
             } = download(session, :report)
    end

    @tag driver: driver
    test "follows redirects before capturing the final download response with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" ->
              %{body: html(~s(<a href="redirect">Download redirected report</a>))}

            "/redirect" ->
              %{status: 302, headers: [{"location", "report"}], body: "redirect body"}

            "/report" ->
              %{
                headers: [
                  {"content-disposition", "attachment; filename=final.csv"},
                  {"content-type", "text/csv"}
                ],
                body: "final bytes"
              }
          end
        end)

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.download(:redirected), fn session ->
        click(session, by_role(:link, name: "Download redirected report"))
      end)
      |> expect(Fluffy.Expect.download_to_have_suggested_filename(:redirected, "final.csv"))
      |> expect(Fluffy.Expect.download_to_have_content(:redirected, "final bytes"))
      |> expect("Download redirected report" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "the download attribute supplies a filename with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" ->
              %{body: html(~s(<a href="raw" download="renamed.txt">Save locally</a>))}

            "/raw" ->
              %{headers: [{"content-type", "text/plain"}], body: "plain bytes"}
          end
        end)

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.download(:raw), &click(&1, by_role(:link, name: "Save locally")))
      |> expect(Fluffy.Expect.download_to_have_suggested_filename(:raw, "renamed.txt"))
      |> expect(Fluffy.Expect.download_to_have_content_type(:raw, "text/plain"))
      |> expect(Fluffy.Expect.download_to_have_content(:raw, "plain bytes"))
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "a timed-out listener is cleaned up with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" ->
              %{body: html(~s(<a href="file" download="after-timeout.txt">Download</a>))}

            "/file" ->
              %{headers: [{"content-type", "text/plain"}], body: "still works"}
          end
        end)

      session = start_test_session(driver)
      session = visit(session, TestHTTPFixtures.path(fixture, "/start"))
      Process.put(:download_action_count, 0)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          wait_for(
            session,
            Event.download(:missing),
            fn session ->
              Process.put(:download_action_count, Process.get(:download_action_count) + 1)
              session
            end,
            timeout: 20
          )
        end

      assert error.message =~ "Expected :download event :missing within 20 ms"
      assert Process.get(:download_action_count) == 1

      session
      |> wait_for(Event.download(:after_timeout), &click(&1, by_role(:link, name: "Download")))
      |> expect(Fluffy.Expect.download_to_have_suggested_filename(:after_timeout, "after-timeout.txt"))
      |> expect(Fluffy.Expect.download_to_have_content(:after_timeout, "still works"))
    end
  end

  @tag driver: :playwright
  test "a target-blank attachment is a download rather than a new page with Playwright" do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body: html(~s(<h1>Download source</h1><a href="report" target="_blank">Download report</a>))
            }

          "/report" ->
            %{
              headers: [
                {"content-disposition", "attachment; filename=orders.csv"},
                {"content-type", "text/csv"}
              ],
              body: "id,total\n1,42\n"
            }
        end
      end)

    :playwright
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/start"))
    |> wait_for(
      Event.download(:report, filename: "orders.csv", url: TestHTTPFixtures.url(fixture, "/report")),
      fn session ->
        click(session, by_role(:link, name: "Download report"))
      end
    )
    |> expect(Fluffy.Expect.download_to_have_suggested_filename(:report, "orders.csv"))
    |> expect(Fluffy.Expect.download_to_have_content(:report, "id,total\n1,42\n"))
    |> expect("Download source" |> by_text() |> to_be_visible())
    |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture, "/start")))
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "filters before retaining bytes and keeps the first matching download with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" ->
              %{
                body:
                  html("""
                  <a href="noise">Noise</a>
                  <a href="wrong">Wrong URL</a>
                  <a href="first">First report</a>
                  <a href="second">Second report</a>
                  """)
              }

            path ->
              filename = if path == "/noise", do: "noise.txt", else: "report.csv"
              bytes = if path in ["/noise", "/wrong"], do: String.duplicate("x", 100), else: path

              %{
                headers: [{"content-disposition", "attachment; filename=#{filename}"}, {"content-type", "text/csv"}],
                body: bytes
              }
          end
        end)

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(
        Event.download(:report,
          filename: ~r/^report\.csv$/,
          url: fn %URI{path: path} ->
            String.ends_with?(path, ["/first", "/second"])
          end,
          max_bytes: 10
        ),
        fn session ->
          session
          |> click(by_role(:link, name: "Noise", exact: true))
          |> click(by_role(:link, name: "Wrong URL"))
          |> click(by_role(:link, name: "First report"))
          |> click(by_role(:link, name: "Second report"))
        end
      )
      |> expect(download_to_have_content(:report, "/first"))
      |> expect(download_to_have_url(:report, fn %URI{path: path} -> String.ends_with?(path, "/first") end))
    end

    @tag driver: driver
    test "unmatched downloads report a missing event with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" -> %{body: html(~s(<a href="file" download="actual.txt">Download</a>))}
            "/file" -> %{headers: [{"content-type", "text/plain"}], body: "ignored"}
          end
        end)

      session = driver |> start_test_session() |> visit(TestHTTPFixtures.path(fixture, "/start"))

      assert_raise ExUnit.AssertionError, ~r/no matching event occurred/, fn ->
        wait_for(
          session,
          Event.download(:missing, filename: "missing.txt", max_bytes: 0, timeout: 500),
          &click(&1, by_role(:link, name: "Download"))
        )
      end
    end
  end

  @tag driver: :playwright, tmp_dir: true
  test "capturing bytes preserves the source download for another consumer", %{tmp_dir: tmp_dir} do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" -> %{body: html(~s(<a href="file" download="shared.txt">Download</a>))}
          "/file" -> %{headers: [{"content-type", "text/plain"}], body: "shared bytes"}
        end
      end)

    session = :playwright |> start_test_session() |> visit(TestHTTPFixtures.path(fixture, "/start"))

    unwrap(session, fn handle ->
      {:ok, waiter} =
        PlaywrightEx.Page.expect_download(handle.page_id, connection: handle.connection, timeout: handle.timeout)

      try do
        wait_for(session, Event.download(:file), &click(&1, by_role(:link, name: "Download")))
        {:ok, download} = PlaywrightEx.Page.await_download(waiter)
        path = Path.join(tmp_dir, "second-copy.txt")
        assert :ok = PlaywrightEx.Download.save_as(download, path, timeout: handle.timeout)
        assert File.read!(path) == "shared bytes"
      after
        PlaywrightEx.EventWaiter.cancel(waiter)
      end
    end)
  end
end
