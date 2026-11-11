defmodule Fluffy.BrowserRuntimeShutdownTest do
  # Stops the application's drivers, so no other test may use them meanwhile.
  use Fluffy.TestCase, async: false

  alias Fluffy.BrowserRuntime

  @moduletag driver: :playwright

  # Needs ftes/playwright_ex#191: closing the driver waits for it to exit.
  test "closing the drivers closes the browsers, and the driver has exited when it returns" do
    browser = fn -> BrowserRuntime.browser() end |> Task.async() |> Task.await(30_000)
    os_pid = driver_os_pid()
    test_process = self()
    PlaywrightEx.Browser.on(browser, :disconnected, fn _browser -> send(test_process, :browser_disconnected) end)
    on_exit(fn -> Supervisor.restart_child(Fluffy.Supervisor, BrowserRuntime.Supervisor) end)

    assert Fluffy.Application.close_drivers() == :ok

    assert_receive :browser_disconnected
    refute os_process_alive?(os_pid)
  end

  defp driver_os_pid do
    driver = PlaywrightEx.Runtime.Heap.get(PlaywrightEx.playwright(Fluffy.PlaywrightDriver), :driverProcess)
    %{port: port} = :sys.get_state(driver)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    os_pid
  end

  defp os_process_alive?(os_pid),
    do: match?({_, 0}, System.cmd("kill", ["-0", to_string(os_pid)], stderr_to_stdout: true))
end
