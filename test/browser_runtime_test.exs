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

    assert_raise ArgumentError, ~r/requires :executable/, fn ->
      Options.validate_playwright!([])
    end

    assert_raise ArgumentError,
                 ~r/:js_logger must be false or a module implementing log\/3/,
                 fn ->
                   Options.validate_playwright!(executable: "playwright", js_logger: true)
                 end
  end
end
