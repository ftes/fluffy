defmodule Fluffy.BrowserRuntimeTest do
  use Fluffy.TestCase, async: true

  alias Fluffy.BrowserRuntime
  alias Fluffy.Options

  test "concurrent first callers initialize one transport and one shared browser" do
    test_process = self()
    runtime_name = Module.concat(__MODULE__, "Runtime#{System.unique_integer([:positive])}")

    start_supervised!(
      {BrowserRuntime,
       name: runtime_name,
       timeout: 100,
       launch_options: [],
       playwright_options: [],
       runtime_supervisor: :unused_in_test,
       playwright_supervisor: :unused_in_test,
       transport_starter: fn _runtime_supervisor, _playwright_supervisor, _options ->
         send(test_process, :transport_started)
         :ok
       end,
       browser_launcher: fn :chromium, _playwright_supervisor, [], 100 ->
         send(test_process, :browser_launched)
         {:ok, %{guid: "shared-browser"}}
       end}
    )

    browser_ids =
      1..20
      |> Task.async_stream(fn _index -> BrowserRuntime.browser_id(runtime_name) end,
        max_concurrency: 20,
        ordered: false
      )
      |> Enum.map(fn {:ok, browser_id} -> browser_id end)

    assert Enum.uniq(browser_ids) == ["shared-browser"]
    assert_receive :transport_started
    assert_receive :browser_launched
    refute_receive :transport_started
    refute_receive :browser_launched
    assert BrowserRuntime.status(runtime_name).launch_count == 1
  end

  @tag :tmp_dir
  test "derives the CLI from assets_dir and preserves explicit executables", %{tmp_dir: directory} do
    assert Options.validate_playwright!(assets_dir: directory)[:executable] ==
             Path.join(directory, "node_modules/playwright/cli.js")

    assert Options.validate_playwright!(assets_dir: directory, executable: "custom")[:executable] ==
             "custom"
  end

  test "validates global Playwright runtime and launch configuration" do
    assert [
             js_logger: Fluffy.Playwright.ConsoleLogger,
             trace_dir: "traces",
             enabled: true,
             engine: :firefox,
             executable: "playwright",
             timeout: 2_000,
             launch_options: [headless: false, slow_mo: 25],
             artifact_dir: nil
           ] =
             Options.validate_playwright!(
               engine: :firefox,
               executable: "playwright",
               timeout: 2_000,
               launch_options: [headless: false, slow_mo: 25],
               artifact_dir: nil
             )

    assert false ==
             Options.validate_playwright!(executable: "playwright", js_logger: false)[:js_logger]

    assert false == Options.validate_playwright!(false)

    assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:mystery/, fn ->
      Options.validate_playwright!(executable: "playwright", mystery: true)
    end

    assert_raise NimbleOptions.ValidationError,
                 ~r/:engine.*invalid value|invalid value.*:engine/,
                 fn ->
                   Options.validate_playwright!(engine: :opera, executable: "playwright")
                 end

    assert Options.validate_playwright!([])[:enabled]

    assert_raise ArgumentError,
                 ~r/:js_logger must be false or a module implementing log\/3/,
                 fn ->
                   Options.validate_playwright!(executable: "playwright", js_logger: true)
                 end
  end

  test "allows a browser launch timeout independent of the global timeout" do
    config = Options.validate_playwright!(timeout: 4_000, launch_options: [timeout: 10_000])

    assert config[:timeout] == 4_000
    assert config[:launch_options][:timeout] == 10_000

    assert_raise NimbleOptions.ValidationError, fn ->
      Options.validate_playwright!(launch_options: [timeout: -1])
    end
  end

  test "treats a nil browser executable path as omitted while validating explicit paths" do
    omitted = Options.validate_playwright!(launch_options: [headless: false])
    nil_path = Options.validate_playwright!(launch_options: [headless: false, executable_path: nil])

    assert nil_path == omitted

    explicit = Options.validate_playwright!(launch_options: [executable_path: "/usr/bin/chromium"])
    assert explicit[:launch_options][:executable_path] == "/usr/bin/chromium"

    assert_raise NimbleOptions.ValidationError, fn ->
      Options.validate_playwright!(launch_options: [executable_path: false])
    end
  end
end

defmodule Fluffy.PlaywrightExecutableDiscoveryTest do
  use ExUnit.Case, async: false

  alias Fluffy.Options

  @tag :tmp_dir
  test "discovers the conventional assets CLI or leaves the dependency default intact", %{tmp_dir: directory} do
    File.cd!(directory, fn ->
      refute Keyword.has_key?(Options.validate_playwright!([]), :executable)

      File.mkdir_p!("assets/node_modules/playwright")
      File.write!("assets/node_modules/playwright/cli.js", "")

      assert Options.validate_playwright!([])[:executable] ==
               Path.join(directory, "assets/node_modules/playwright/cli.js")

      assert Options.validate_playwright!(executable: "custom")[:executable] == "custom"
    end)
  end
end
