defmodule Fluffy.Conformance.DownloadEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Download
  alias Fluffy.Event
  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver, tmp_dir: true
    test "download handles keep the source page and can be read and saved repeatedly with #{driver}", %{
      driver: driver,
      tmp_dir: tmp_dir
    } do
      session = session(driver)
      pending = wait_for(session, Event.download())
      click(session, by_role(:link, name: "Report", exact: true))
      download = await(pending)
      assert download.suggested_filename == "report.csv"
      assert String.ends_with?(download.url, "/report")
      assert download |> Download.page() |> Fluffy.Page.url() |> String.ends_with?("/start")
      assert Download.read(download) == "id,total\n1,42\n"
      assert Download.read(download) == "id,total\n1,42\n"
      destination = Path.join(tmp_dir, "copy.csv")
      assert Download.save_as(download, destination) == :ok

      session
      |> expect(page_to_have_url(&String.ends_with?(&1.path, "/start")))
      |> expect("Source" |> by_text() |> to_be_visible())

      if driver == :playwright do
        assert Download.page(download) == Fluffy.Playwright.current_page(session)
        assert unwrap_and_return(download, &PlaywrightEx.Download.suggested_filename/1) == "report.csv"
      else
        assert_raise Fluffy.CapabilityError, ~r/no native counterpart/, fn -> unwrap_and_return(download, & &1) end
      end

      close_session(session)
      assert File.read!(destination) == "id,total\n1,42\n"
      assert_raise ArgumentError, ~r/session is closed/, fn -> Download.read(download) end
    end

    @tag driver: driver
    test "path raises once its session is closed with #{driver}", %{driver: driver} do
      session = session(driver)
      pending = wait_for(session, Event.download())
      click(session, by_role(:link, name: "Report", exact: true))
      download = await(pending)

      close_session(session)
      assert_raise ArgumentError, ~r/session is closed/, fn -> Download.path(download) end
    end

    @tag driver: driver
    test "predicates skip unrelated downloads and retain the first match with #{driver}", %{driver: driver} do
      session = session(driver)
      pending = wait_for(session, Event.download(&(&1.suggested_filename == "report.csv")))

      session
      |> click(by_role(:link, name: "Noise", exact: true))
      |> click(by_role(:link, name: "Report", exact: true))
      |> click(by_role(:link, name: "Renamed", exact: true))

      assert Download.read(await(pending)) == "id,total\n1,42\n"
    end

    @tag driver: driver
    test "two waits observe the same physical download with #{driver}", %{driver: driver} do
      session = session(driver)
      first = wait_for(session, Event.download())
      second = wait_for(session, Event.download())
      click(session, by_role(:link, name: "Report", exact: true))
      assert await(first) == await(second)
    end

    @tag driver: driver
    test "redirects resolve to the final download with #{driver}", %{driver: driver} do
      driver
      |> session()
      |> expect_event(Event.download(), &click(&1, by_role(:link, name: "Redirect", exact: true)), fn download ->
        assert download.suggested_filename == "report.csv"
        assert Download.read(download) == "id,total\n1,42\n"
      end)
      |> expect("Source" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "the download attribute supplies the filename with #{driver}", %{driver: driver} do
      driver
      |> session()
      |> expect_event(Event.download(), &click(&1, by_role(:link, name: "Renamed", exact: true)), fn download ->
        assert download.suggested_filename == "renamed.txt"
        assert Download.read(download) == "plain bytes"
      end)
    end

    @tag driver: driver
    test "size limits apply when reading, not when observing a download with #{driver}", %{driver: driver} do
      driver
      |> session()
      |> expect_event(Event.download(), &click(&1, by_role(:link, name: "Report", exact: true)), fn download ->
        assert download.suggested_filename == "report.csv"
        assert_raise ExUnit.AssertionError, ~r/max_bytes/, fn -> Download.read(download, max_bytes: 1) end
        assert Download.read(download) == "id,total\n1,42\n"
      end)
    end

    @tag driver: driver
    test "a timeout releases its registration before the next download with #{driver}", %{driver: driver} do
      session = session(driver)
      pending = wait_for(session, Event.download(), timeout: 0)
      assert_raise ExUnit.AssertionError, ~r/timeout/, fn -> await(pending) end
      expect_event(session, Event.download(), &click(&1, by_role(:link, name: "Report", exact: true)))
    end

    @tag driver: driver
    test "a rejected download times out with #{driver}", %{driver: driver} do
      session = session(driver)
      pending = wait_for(session, Event.download(fn _ -> false end), timeout: 500)
      click(session, by_role(:link, name: "Report", exact: true))
      assert_raise ExUnit.AssertionError, ~r/no matching download event/, fn -> await(pending) end
    end

    @tag driver: driver
    test "downloads leave the source document intact without registrations with #{driver}", %{driver: driver} do
      driver
      |> session()
      |> click(by_role(:link, name: "Report", exact: true))
      |> expect("Source" |> by_text() |> to_be_visible())
    end
  end

  @tag driver: :phoenix
  test "a Phoenix download is held in memory and has no file" do
    session = session(:phoenix)
    pending = wait_for(session, Event.download())
    click(session, by_role(:link, name: "Report", exact: true))
    download = await(pending)

    error = assert_raise Fluffy.CapabilityError, fn -> Download.path(download) end
    assert error.capability == :download_path
    assert Download.read(download) == "id,total\n1,42\n"
  end

  @tag driver: :playwright
  test "path returns the downloaded file" do
    session = session(:playwright)
    pending = wait_for(session, Event.download())
    click(session, by_role(:link, name: "Report", exact: true))
    download = await(pending)

    path = Download.path(download)
    assert File.read!(path) == "id,total\n1,42\n"
  end

  @tag driver: :playwright
  test "a target-blank attachment is a download" do
    :playwright
    |> session()
    |> expect_event(Event.download(), &click(&1, by_role(:link, name: "New tab", exact: true)), fn download ->
      assert %Fluffy.Page{} = Download.page(download)
      assert Download.read(download) == "id,total\n1,42\n"
    end)
    |> expect("Source" |> by_text() |> to_be_visible())
  end

  @tag driver: :playwright
  test "download metadata is available before completion, while read waits for the bytes" do
    owner = self()
    first = "first" <> TestHTTPFixtures.sniff_padding()

    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{body: ~s(<a href="slow">Download</a>)}

          "/slow" ->
            %{
              headers: [{"content-disposition", "attachment; filename=slow.txt"}],
              stream: fn conn ->
                {:ok, conn} = Plug.Conn.chunk(conn, first)
                send(owner, {:stream, self()})

                receive do
                  :finish -> :ok
                after
                  30_000 -> :ok
                end

                {:ok, conn} = Plug.Conn.chunk(conn, "last")
                conn
              end
            }
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))

    pending = wait_for(session, Event.download())
    click(session, by_role(:link, name: "Download"))
    assert_receive {:stream, server}, Fluffy.Session.timeout(session)

    try do
      download = await(pending)
      assert download.suggested_filename == "slow.txt"
      reader = Task.async(fn -> Download.read(download) end)
      assert Task.yield(reader, 20) == nil
      send(server, :finish)
      assert Task.await(reader) == first <> "last"
    after
      send(server, :finish)
    end
  end

  @tag driver: :playwright, tmp_dir: true, capture_log: true
  @tag skip:
         if(playwright_engine?(:firefox),
           do: "Firefox never completes or fails an interrupted download"
         )
  test "failed downloads expose metadata but raise when reading, saving or getting the path", %{tmp_dir: tmp_dir} do
    owner = self()

    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{body: ~s(<a href="broken">Download</a>)}

          "/broken" ->
            %{
              headers: [{"content-disposition", "attachment; filename=broken.txt"}],
              stream: fn conn ->
                {:ok, _conn} = Plug.Conn.chunk(conn, "partial" <> TestHTTPFixtures.sniff_padding())
                send(owner, {:stream, self()})

                receive do
                  :abort -> exit(:shutdown)
                after
                  30_000 -> exit(:shutdown)
                end
              end
            }
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))

    pending = wait_for(session, Event.download())
    click(session, by_role(:link, name: "Download"))
    assert_receive {:stream, server}, Fluffy.Session.timeout(session)
    download = await(pending)
    assert download.suggested_filename == "broken.txt"
    send(server, :abort)

    error = assert_raise Fluffy.OperationError, fn -> Download.read(download) end
    assert %{operation: :read, cause: %PlaywrightEx.PlaywrightError{}} = error
    assert error.cause.message =~ "download.saveAs"

    error = assert_raise Fluffy.OperationError, fn -> Download.save_as(download, Path.join(tmp_dir, "copy.txt")) end
    assert %{operation: :save_as, cause: %PlaywrightEx.PlaywrightError{}} = error
    assert error.cause.message =~ "download.saveAs"

    assert %{operation: :path, cause: %PlaywrightEx.PlaywrightError{}} =
             assert_raise(Fluffy.OperationError, fn -> Download.path(download) end)
  end

  defp session(driver) do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body: """
              <!doctype html><html><body><h1>Source</h1>
              <a href="report">Report</a>
              <a href="report" target="_blank">New tab</a>
              <a href="redirect">Redirect</a>
              <a href="raw" download="renamed.txt">Renamed</a>
              <a href="noise" download="noise.txt">Noise</a>
              </body></html>
              """
            }

          "/redirect" ->
            %{status: 302, headers: [{"location", "report"}], body: "redirect"}

          "/report" ->
            %{
              headers: [{"content-disposition", "attachment; filename=report.csv"}, {"content-type", "text/csv"}],
              body: "id,total\n1,42\n"
            }

          "/raw" ->
            %{headers: [{"content-type", "text/plain"}], body: "plain bytes"}

          "/noise" ->
            %{headers: [{"content-type", "text/plain"}], body: "ignored"}
        end
      end)

    driver
    |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
    |> visit(TestHTTPFixtures.path(fixture, "/start"))
  end
end
