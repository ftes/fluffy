defmodule Fluffy.PlaywrightDriverLossTest do
  # Kills the shared driver, so it runs after the async tests that use it.
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  @moduletag driver: :playwright, capture_log: true

  test "a lost driver stops running sessions and a new session relaunches the browser" do
    session = session_for_html(:playwright, "<button>Save</button>")
    runtime = session.runtime
    monitor = monitor_running(runtime)

    kill_driver()

    # The driver's loss closes the browser context, which stops the session.
    assert_receive {:DOWN, ^monitor, :process, ^runtime, :normal}, 5_000

    started = System.monotonic_time(:millisecond)
    assert_raise ArgumentError, "session is closed", fn -> click(session, by_role(:button, name: "Save")) end
    assert System.monotonic_time(:millisecond) - started < 1_000

    :playwright
    |> session_for_html("<button>Save</button>")
    |> click(by_role(:button, name: "Save"))
    |> expect(:button |> by_role(name: "Save") |> to_be_visible())
  end

  # The lost driver closes the action's page too; that is no page closing itself.
  test "a driver lost during an action fails the action" do
    session = session_for_html(:playwright, "<button disabled>Save</button>")

    {:ok, _killer} =
      Task.start(fn ->
        Process.sleep(200)
        kill_driver()
      end)

    assert_raise Fluffy.OperationError, ~r/closed/, fn ->
      click(session, by_role(:button, name: "Save"), timeout: 5_000)
    end
  end

  defp kill_driver do
    driver = PlaywrightEx.Runtime.Heap.get(PlaywrightEx.playwright(Fluffy.PlaywrightDriver), :driverProcess)
    %{port: port} = :sys.get_state(driver)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    {_, 0} = System.cmd("kill", ["-9", to_string(os_pid)])
  end
end
