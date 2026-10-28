defmodule Fluffy.PlaywrightTraceTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.FilePayload
  alias Fluffy.Playwright
  alias Fluffy.TestHTTPFixtures
  alias Fluffy.TestScope
  alias Fluffy.TestWeb.Endpoint

  test "saves a multi-page context trace before scope cleanup closes the browser", context do
    directory = trace_directory(context)

    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{body: html(~s|<button onclick="window.open('popup')">Open popup</button>|)}

          "/popup" ->
            %{body: html("<h1>Traced popup</h1>")}
        end
      end)

    :playwright
    |> start_session(base_url: Fluffy.TestServer.base_url())
    |> Playwright.trace(directory: directory, name: "checkout trace", open: false)
    |> visit(TestHTTPFixtures.path(fixture, "/start"))
    |> then(fn session ->
      pending = wait_for(session, Event.popup())
      click(session, by_role(:button, name: "Open popup"))
      switch_page(session, await(pending))
    end)
    |> expect("Traced popup" |> by_text() |> to_be_visible())

    :ok = GenServer.stop(TestScope.current())

    assert [path] = Path.wildcard(Path.join(directory, "checkout-trace-*.zip"))
    assert File.stat!(path).size > 0
    assert {:ok, _files} = :zip.list_dir(String.to_charlist(path))
  end

  test "separate sessions save separate traces", context do
    directory = trace_directory(context)

    for name <- ["first", "second"] do
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> Playwright.trace(directory: directory, name: name, open: false)
      |> visit("/stage")
    end

    :ok = GenServer.stop(TestScope.current())

    assert [_first] = Path.wildcard(Path.join(directory, "first-*.zip"))
    assert [_second] = Path.wildcard(Path.join(directory, "second-*.zip"))
  end

  test "trace archives do not copy in-memory upload contents", context do
    directory = trace_directory(context)
    secret = "FLUFFY-UPLOAD-SECRET-#{System.unique_integer([:positive])}"

    :playwright
    |> session_for_html(
      ~s(<label>Attachment <input type="file"></label>),
      base_url: Fluffy.TestServer.base_url()
    )
    |> Playwright.trace(directory: directory, name: "upload privacy", open: false)
    |> set_input_files(
      by_label("Attachment"),
      %FilePayload{name: "private.txt", bytes: secret, content_type: "text/plain"}
    )

    :ok = GenServer.stop(TestScope.current())

    assert [path] = Path.wildcard(Path.join(directory, "upload-privacy-*.zip"))
    assert {:ok, entries} = :zip.extract(String.to_charlist(path), [:memory])

    refute Enum.any?(entries, fn {_name, contents} ->
             :binary.match(contents, secret) != :nomatch
           end)
  end

  test "coverage records instrumented page coverage in the trace archive", context do
    directory = trace_directory(context)
    body = "<script>window.__coverage__ = #{istanbul_coverage()}</script><h1>Covered</h1>"
    fixture = TestHTTPFixtures.register(fn _request -> %{body: html(body)} end)

    for {name, options} <- [{"with coverage", [coverage: true]}, {"without coverage", []}] do
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> Playwright.trace([directory: directory, name: name, open: false] ++ options)
      |> visit(TestHTTPFixtures.path(fixture, "/covered"))
      |> expect("Covered" |> by_text() |> to_be_visible())
    end

    :ok = GenServer.stop(TestScope.current())

    assert %{~c"trace.coverage" => coverage} = trace_entries(directory, "with-coverage-*.zip")
    assert coverage =~ "fluffy/covered.js"
    refute Map.has_key?(trace_entries(directory, "without-coverage-*.zip"), ~c"trace.coverage")
  end

  test "trace is Playwright-only" do
    session =
      start_session(:phoenix,
        endpoint: Endpoint,
        base_url: Fluffy.TestServer.base_url()
      )

    assert_raise Fluffy.CapabilityError, fn ->
      Playwright.trace(session, open: false)
    end
  end

  test "a session cannot start tracing twice", context do
    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> Playwright.trace(directory: trace_directory(context), open: false)

    assert_raise ArgumentError, ~r/already tracing/, fn ->
      Playwright.trace(session, directory: trace_directory(context), open: false)
    end
  end

  test "LiveView navigation bookkeeping costs one browser call per action", context do
    directory = trace_directory(context)

    :playwright
    |> start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)
    |> Playwright.trace(directory: directory, name: "round-trips", open: false)
    |> visit("/live/chamber-map")
    |> click(by_text("Saves: 0"))
    |> click(by_text("Saves: 0"))

    :ok = GenServer.stop(TestScope.current())

    calls =
      for {name, body} <- trace_entries(directory, "round-trips-*.zip"),
          List.to_string(name) =~ ~r/\.trace$/,
          line <- String.split(body, "\n", trim: true),
          %{"type" => "before", "class" => "Frame", "method" => method} <- [Jason.decode!(line)],
          do: method

    assert calls == ~w(goto waitForFunction click evaluateExpression click evaluateExpression)
  end

  defp trace_directory(context) do
    path =
      Path.join(
        System.tmp_dir!(),
        "fluffy-trace-test-#{context.test}-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  defp trace_entries(directory, pattern) do
    assert [path] = Path.wildcard(Path.join(directory, pattern))
    assert {:ok, entries} = :zip.extract(String.to_charlist(path), [:memory])
    Map.new(entries)
  end

  defp istanbul_coverage do
    location = %{start: %{line: 1, column: 0}, end: %{line: 1, column: 10}}

    JSON.encode!(%{
      "fluffy/covered.js" => %{
        path: "fluffy/covered.js",
        statementMap: %{"0" => location},
        fnMap: %{},
        branchMap: %{},
        s: %{"0" => 1},
        f: %{},
        b: %{}
      }
    })
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end
