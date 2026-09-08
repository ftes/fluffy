defmodule Fluffy.PlaywrightEventListenerTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Playwright.NavigationObserver
  alias Fluffy.Playwright.SubscriptionRegistry

  @tag driver: :playwright
  test "a navigation observer stops and releases its subscription when its owner exits" do
    test_pid = self()
    session = session_for_html(:playwright, "<p>Observer owner</p>")

    unwrap(session, fn handle ->
      key = {handle.context_id, :response}
      baseline = Map.fetch!(:sys.get_state(SubscriptionRegistry), key)

      owner =
        spawn(fn ->
          %NavigationObserver{listener: listener} =
            NavigationObserver.arm(
              handle.context_id,
              handle.page_id,
              handle.frame_id,
              handle.timeout
            )

          send(test_pid, {:owned_listener, listener})

          receive do
            :finish -> :ok
          end
        end)

      assert_receive {:owned_listener, listener}
      assert Process.alive?(listener)
      assert Map.fetch!(:sys.get_state(SubscriptionRegistry), key) == baseline + 1

      reference = Process.monitor(listener)
      send(owner, :finish)

      assert_receive {:DOWN, ^reference, :process, ^listener, :normal}
      assert Map.fetch!(:sys.get_state(SubscriptionRegistry), key) == baseline
    end)
  end
end
