defmodule Fluffy.BrowserRuntimeTest do
  use Fluffy.TestCase, async: true

  alias Fluffy.BrowserRuntime
  alias Fluffy.Options

  test "concurrent first callers initialize one transport and one shared browser" do
    runtime_name = start_runtime(self())

    browsers =
      1..20
      |> Task.async_stream(fn _index -> BrowserRuntime.browser(runtime_name) end,
        max_concurrency: 20,
        ordered: false
      )
      |> Enum.map(fn {:ok, browser} -> browser end)

    assert Enum.uniq(browsers) == [%{guid: "browser-1"}]
    assert_receive :transport_started
    assert_receive {:browser_launched, [timeout: 100]}
    refute_receive :transport_started
    refute_receive {:browser_launched, _options}
    assert BrowserRuntime.status(runtime_name).launch_count == 1
  end

  test "relaunches after the browser disconnects" do
    runtime_name = start_runtime(self())
    assert %{guid: "browser-1"} = BrowserRuntime.browser(runtime_name)

    send(Process.whereis(runtime_name), {:browser_disconnected, "stale-browser"})
    assert %{guid: "browser-1"} = BrowserRuntime.browser(runtime_name)

    send(Process.whereis(runtime_name), {:browser_disconnected, "browser-1"})
    assert %{guid: "browser-2"} = BrowserRuntime.browser(runtime_name)
    assert BrowserRuntime.status(runtime_name).launch_count == 2
  end

  test "replaces a lost browser before its disconnect arrives" do
    runtime_name = start_runtime(self())
    lost = BrowserRuntime.browser(runtime_name)

    assert %{guid: "browser-2"} = replacement = BrowserRuntime.replace(runtime_name, lost)
    assert BrowserRuntime.replace(runtime_name, lost) == replacement
    assert BrowserRuntime.browser(runtime_name) == replacement
    assert BrowserRuntime.status(runtime_name).launch_count == 2
    assert_receive {:browser_closed, ^lost}
    refute_receive {:browser_closed, _browser}
  end

  test "replaces a lost browser without waiting for it to close" do
    test_process = self()

    runtime_name =
      start_runtime(test_process, counting_launch(), fn browser ->
        send(test_process, {:closing, browser, self()})
        Process.sleep(:infinity)
      end)

    lost = BrowserRuntime.browser(runtime_name)

    assert %{guid: "browser-2"} = BrowserRuntime.replace(runtime_name, lost)
    assert_receive {:closing, ^lost, closer}
    ref = Process.monitor(closer)
    assert Process.alive?(closer)
    # The close is bounded by the runtime's timeout.
    assert_receive {:DOWN, ^ref, :process, ^closer, _reason}, 1_000
  end

  test "a failed launch raises in the caller and leaves the runtime to retry" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    runtime_name =
      start_runtime(self(), fn ->
        case Agent.get_and_update(attempts, &{&1 + 1, &1 + 1}) do
          1 -> {:error, %PlaywrightEx.PlaywrightError{message: "Executable doesn't exist"}}
          _ -> {:ok, %{guid: "browser-1"}}
        end
      end)

    runtime = Process.whereis(runtime_name)

    assert_raise RuntimeError, "could not launch the Playwright chromium browser: Executable doesn't exist", fn ->
      BrowserRuntime.browser(runtime_name)
    end

    assert Process.whereis(runtime_name) == runtime
    assert BrowserRuntime.status(runtime_name).launch_count == 0
    assert %{guid: "browser-1"} = BrowserRuntime.browser(runtime_name)
  end

  test "a launch that raises raises in the caller without crashing the runtime" do
    runtime_name = start_runtime(self(), fn -> raise ArgumentError, "unknown options [:headles]" end)
    runtime = Process.whereis(runtime_name)

    assert_raise RuntimeError, "could not launch the Playwright chromium browser: unknown options [:headles]", fn ->
      BrowserRuntime.browser(runtime_name)
    end

    assert Process.whereis(runtime_name) == runtime
    assert BrowserRuntime.status(runtime_name).launch_count == 0
  end

  @tag driver: :playwright
  test "invalid launch options raise in the caller without crashing the runtime" do
    runtime_supervisor = start_supervised!(DynamicSupervisor)
    playwright_name = Module.concat(__MODULE__, "Driver#{System.unique_integer([:positive])}")

    runtime =
      start_supervised!(
        {BrowserRuntime,
         name: Module.concat(playwright_name, Runtime),
         engine: Application.fetch_env!(:fluffy, :playwright)[:engine],
         timeout: 15_000,
         launch_options: [headles: true],
         playwright_options: [],
         playwright_name: playwright_name,
         runtime_supervisor: runtime_supervisor}
      )

    assert_raise RuntimeError, ~r/could not launch the Playwright \w+ browser: .*headles/, fn ->
      BrowserRuntime.browser(runtime)
    end

    assert Process.alive?(runtime)
  end

  @tag driver: :playwright, capture_log: true
  test "relaunches against a restarted driver after the driver process dies" do
    runtime_supervisor = start_supervised!(DynamicSupervisor)
    playwright_name = Module.concat(__MODULE__, "Driver#{System.unique_integer([:positive])}")

    runtime =
      start_supervised!(
        {BrowserRuntime,
         name: Module.concat(playwright_name, Runtime),
         engine: Application.fetch_env!(:fluffy, :playwright)[:engine],
         timeout: 15_000,
         launch_options: [],
         playwright_options: [],
         playwright_name: playwright_name,
         runtime_supervisor: runtime_supervisor}
      )

    lost = BrowserRuntime.browser(runtime)
    driver = PlaywrightEx.Runtime.Heap.get(PlaywrightEx.playwright(playwright_name), :driverProcess)
    %{port: port} = :sys.get_state(driver)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    {_, 0} = System.cmd("kill", ["-9", to_string(os_pid)])

    assert_eventually(fn -> BrowserRuntime.status(runtime).browser == nil end)
    browser = BrowserRuntime.browser(runtime)
    refute PlaywrightEx.Browser.is_connected(lost)
    assert PlaywrightEx.Browser.is_connected(browser)
    assert BrowserRuntime.status(runtime).launch_count == 2
  end

  test "validates global Playwright runtime configuration" do
    config =
      Options.validate_playwright!(
        engine: :firefox,
        executable: "playwright",
        timeout: 2_000,
        launch_options: [headless: false, slow_mo: 25],
        artifact_dir: nil
      )

    assert Enum.sort(config) ==
             Enum.sort(
               trace_dir: "traces",
               log_browser_console: true,
               enabled: true,
               engine: :firefox,
               executable: "playwright",
               timeout: 2_000,
               launch_options: [headless: false, slow_mo: 25],
               artifact_dir: nil
             )

    refute Options.validate_playwright!(log_browser_console: false)[:log_browser_console]
    assert false == Options.validate_playwright!(false)

    assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:js_logger/, fn ->
      Options.validate_playwright!(js_logger: false)
    end

    assert_raise NimbleOptions.ValidationError,
                 ~r/:engine.*invalid value|invalid value.*:engine/,
                 fn ->
                   Options.validate_playwright!(engine: :opera)
                 end

    assert Options.validate_playwright!([])[:enabled]
    refute Keyword.has_key?(Options.validate_playwright!([]), :executable)
  end

  test "passes launch options through, including a launch timeout independent of the global timeout" do
    config = Options.validate_playwright!(timeout: 4_000, launch_options: [timeout: 10_000, channel: "chrome"])

    assert config[:timeout] == 4_000
    assert config[:launch_options] == [timeout: 10_000, channel: "chrome"]
  end

  defp assert_eventually(fun, attempts \\ 500)
  defp assert_eventually(fun, 0), do: assert(fun.())

  defp assert_eventually(fun, attempts) do
    if !fun.() do
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end

  defp start_runtime(test_process), do: start_runtime(test_process, counting_launch())

  defp start_runtime(test_process, launch) do
    start_runtime(test_process, launch, fn browser ->
      send(test_process, {:browser_closed, browser})
      :ok
    end)
  end

  defp counting_launch do
    {:ok, launches} = Agent.start_link(fn -> 0 end)
    fn -> {:ok, %{guid: "browser-#{Agent.get_and_update(launches, &{&1 + 1, &1 + 1})}"}} end
  end

  defp start_runtime(test_process, launch, close) do
    runtime_name = Module.concat(__MODULE__, "Runtime#{System.unique_integer([:positive])}")

    start_supervised!(
      {BrowserRuntime,
       name: runtime_name,
       timeout: 100,
       launch_options: [],
       playwright_options: [],
       runtime_supervisor: :unused_in_test,
       playwright_name: :unused_in_test,
       transport_starter: fn _runtime_supervisor, _playwright_name, _options ->
         send(test_process, :transport_started)
         :ok
       end,
       browser_launcher: fn :chromium, _playwright_name, options ->
         send(test_process, {:browser_launched, options})
         launch.()
       end,
       browser_closer: close}
    )

    runtime_name
  end
end
