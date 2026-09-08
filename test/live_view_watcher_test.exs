defmodule Fluffy.LiveViewWatcherTest do
  use Fluffy.TestCase, async: true

  alias Fluffy.LiveViewWatcher

  test "reports process death promptly and terminates" do
    view_pid = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, watcher} =
      start_supervised({LiveViewWatcher, caller: self(), view: %{pid: view_pid}},
        id: make_ref()
      )

    watcher_reference = Process.monitor(watcher)
    Process.exit(view_pid, :kill)

    assert_receive {:fluffy_live_view, ^watcher, {:died, :killed}}, 100
    assert_receive {:DOWN, ^watcher_reference, :process, ^watcher, :normal}, 100
  end
end
