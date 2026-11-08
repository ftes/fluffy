defmodule Fluffy.BrowserRuntimeTest do
  use Fluffy.TestCase, async: true

  alias Fluffy.Backend
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

    disconnect(runtime_name, "stale-browser")
    assert %{guid: "browser-1"} = BrowserRuntime.browser(runtime_name)

    disconnect(runtime_name, "browser-1")
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

  describe "a pool of browsers" do
    test "starts no driver or browser before a session needs one" do
      runtime_name = start_pool(self(), 3)

      assert %{initialized?: false, launch_count: 0} = BrowserRuntime.status(runtime_name)
      refute_receive :transport_started
      refute_receive {:browser_launched, _options}
    end

    test "sequential sessions reuse one browser" do
      runtime_name = start_pool(self(), 3)

      first = BrowserRuntime.browser(runtime_name)
      BrowserRuntime.release(runtime_name)

      assert BrowserRuntime.browser(runtime_name) == first
      assert BrowserRuntime.status(runtime_name).launch_count == 1
    end

    test "concurrent sessions go to the least-loaded browser, ties to the lowest slot" do
      runtime_name = start_pool(self(), 2)

      assert {_owner, %{guid: "browser-1"}} = start_owner(runtime_name)
      assert {_owner, %{guid: "browser-2"}} = start_owner(runtime_name)
      assert {_owner, %{guid: "browser-1"}} = start_owner(runtime_name)

      assert loads(runtime_name) == [2, 1]
      assert BrowserRuntime.status(runtime_name).launch_count == 2
    end

    test "one process keeps its browser and counts once" do
      runtime_name = start_pool(self(), 2)

      first = BrowserRuntime.browser(runtime_name)

      assert BrowserRuntime.browser(runtime_name) == first
      assert loads(runtime_name) == [1, 0]
    end

    test "a session's end frees its slot, even when its process crashes" do
      runtime_name = start_pool(self(), 2)

      {owner, first} = start_owner(runtime_name)
      {_owner, _second} = start_owner(runtime_name)
      Process.unlink(owner)
      Process.exit(owner, :kill)
      assert_eventually(fn -> loads(runtime_name) == [0, 1] end)

      assert {_owner, ^first} = start_owner(runtime_name)
      assert BrowserRuntime.status(runtime_name).launch_count == 2
    end

    test "a slot launching a browser blocks only the sessions bound to it" do
      runtime_name = start_pool(self(), 3, blocking_launch(self(), 2))

      {_owner, first} = start_owner(runtime_name)
      spawn_owner(runtime_name)
      assert_receive {:launching, slot}

      assert %{guid: "browser-3"} = BrowserRuntime.browser(runtime_name)
      assert {_owner, ^first} = start_owner(runtime_name)

      send(slot, :finish_launch)
      assert_receive {:owner_browser, _owner, %{guid: "browser-2"}}
    end

    test "a disconnect relaunches only that slot's browser" do
      runtime_name = start_pool(self(), 2)
      {_owner, first} = start_owner(runtime_name)
      {_owner, second} = start_owner(runtime_name)

      disconnect(runtime_name, first.guid)

      assert [nil, ^second] = Enum.map(BrowserRuntime.status(runtime_name).slots, & &1.browser)
      assert {_owner, %{guid: "browser-3"}} = start_owner(runtime_name)
      assert [%{guid: "browser-3"}, ^second] = Enum.map(BrowserRuntime.status(runtime_name).slots, & &1.browser)
    end

    test "replacing a lost browser relaunches the caller's slot" do
      runtime_name = start_pool(self(), 2)
      lost = BrowserRuntime.browser(runtime_name)
      {_owner, other} = start_owner(runtime_name)

      assert %{guid: "browser-3"} = BrowserRuntime.replace(runtime_name, lost)
      assert [%{guid: "browser-3"}, ^other] = Enum.map(BrowserRuntime.status(runtime_name).slots, & &1.browser)
      assert_receive {:browser_closed, ^lost}, 5_000
      refute_receive {:browser_closed, _browser}
    end

    test "the default size keeps one browser shared by every session" do
      runtime_name = start_runtime(self())

      {_owner, first} = start_owner(runtime_name)
      assert {_owner, ^first} = start_owner(runtime_name)

      assert loads(runtime_name) == [2]
      assert BrowserRuntime.status(runtime_name).launch_count == 1
    end

    test "shutting down closes every launched browser" do
      runtime_name = start_pool(self(), 2)
      {_owner, first} = start_owner(runtime_name)
      {_owner, second} = start_owner(runtime_name)

      stop_supervised!(BrowserRuntime)

      assert_received {:browser_closed, ^first}
      assert_received {:browser_closed, ^second}
    end

    @tag driver: :playwright, capture_log: true
    test "launches real browsers lazily and relaunches one independently" do
      runtime_supervisor = start_supervised!(DynamicSupervisor)
      playwright_name = Module.concat(__MODULE__, "Driver#{System.unique_integer([:positive])}")

      runtime =
        start_supervised!(
          {BrowserRuntime,
           name: Module.concat(playwright_name, Runtime),
           engine: Application.fetch_env!(:fluffy, :playwright)[:engine],
           timeout: 15_000,
           pool_size: 2,
           launch_options: [],
           playwright_options: [],
           playwright_name: playwright_name,
           runtime_supervisor: runtime_supervisor}
        )

      assert %{initialized?: false, launch_count: 0} = BrowserRuntime.status(runtime)
      assert Process.whereis(playwright_name) == nil

      {_owner, first} = start_owner(runtime)
      {_owner, second} = start_owner(runtime)
      assert first.guid != second.guid

      PlaywrightEx.Browser.close(first)

      assert_eventually(fn -> Enum.map(BrowserRuntime.status(runtime).slots, & &1.browser) == [nil, second] end)
      assert PlaywrightEx.Browser.is_connected(second)
    end

    @tag driver: :playwright
    test "a session holds its slot until it closes" do
      session = Fluffy.start_session(:playwright, base_url: Fluffy.TestServer.base_url())
      assert assigned?(session.runtime)

      Fluffy.close_session(session)

      refute assigned?(session.runtime)
    end

    @tag driver: :playwright, capture_log: true
    test "a session whose test process crashes frees its slot" do
      test_process = self()

      {owner, _ref} =
        spawn_monitor(fn ->
          send(
            test_process,
            {:session, Backend.start_unmanaged_session(:playwright, base_url: Fluffy.TestServer.base_url())}
          )

          Process.sleep(:infinity)
        end)

      assert_receive {:session, session}, 30_000
      assert assigned?(session.runtime)

      Process.exit(owner, :kill)

      assert_eventually(fn -> not assigned?(session.runtime) end)
    end
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
               pool_size: 1,
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

    assert Options.validate_playwright!(pool_size: 4)[:pool_size] == 4

    for invalid <- [0, -1, 1.5, :half] do
      assert_raise NimbleOptions.ValidationError, ~r/:pool_size/, fn ->
        Options.validate_playwright!(pool_size: invalid)
      end
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

  defp start_runtime(test_process, launch), do: start_runtime(test_process, launch, notifying_close(test_process))

  defp start_pool(test_process, pool_size, launch \\ counting_launch()) do
    start_runtime(test_process, launch, notifying_close(test_process), pool_size: pool_size)
  end

  defp notifying_close(test_process) do
    fn browser ->
      send(test_process, {:browser_closed, browser})
      :ok
    end
  end

  defp counting_launch do
    {:ok, launches} = Agent.start_link(fn -> 0 end)
    fn -> {:ok, %{guid: "browser-#{Agent.get_and_update(launches, &{&1 + 1, &1 + 1})}"}} end
  end

  # Blocks the `blocked`th launch in its slot until the test sends `:finish_launch`.
  defp blocking_launch(test_process, blocked) do
    {:ok, launches} = Agent.start_link(fn -> 0 end)

    fn ->
      launch = Agent.get_and_update(launches, &{&1 + 1, &1 + 1})

      if launch == blocked do
        send(test_process, {:launching, self()})

        receive do
          :finish_launch -> :ok
        end
      end

      {:ok, %{guid: "browser-#{launch}"}}
    end
  end

  # A separate process stands in for a session: its load lasts as long as it does.
  defp spawn_owner(runtime_name) do
    test_process = self()

    spawn_link(fn ->
      send(test_process, {:owner_browser, self(), BrowserRuntime.browser(runtime_name)})
      Process.sleep(:infinity)
    end)
  end

  defp start_owner(runtime_name) do
    owner = spawn_owner(runtime_name)
    assert_receive {:owner_browser, ^owner, browser}, 30_000
    {owner, browser}
  end

  defp loads(runtime_name), do: Enum.map(BrowserRuntime.status(runtime_name).slots, & &1.load)

  # The disconnect listener sends to the slot that launched the browser.
  defp disconnect(runtime_name, guid) do
    for %{pid: slot} <- BrowserRuntime.status(runtime_name).slots do
      send(slot, {:browser_disconnected, guid})
    end
  end

  defp assigned?(runtime), do: Map.has_key?(:sys.get_state(BrowserRuntime).assignments, runtime)

  defp start_runtime(test_process, launch, close, options \\ []) do
    runtime_name = Module.concat(__MODULE__, "Runtime#{System.unique_integer([:positive])}")

    start_supervised!(
      {BrowserRuntime,
       [
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
         browser_closer: close
       ] ++ options}
    )

    runtime_name
  end
end
