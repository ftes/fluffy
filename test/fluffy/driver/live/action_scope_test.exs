defmodule Fluffy.Driver.Live.ActionScopeTest do
  use ExUnit.Case, async: true

  alias Fluffy.Driver.Live.ActionScope

  test "a nested scope leaves the enclosing scope as it was" do
    ActionScope.run(fn ->
      ActionScope.record_delivery()
      ActionScope.run(fn -> refute ActionScope.delivered?() end)
      assert ActionScope.delivered?()
    end)

    refute ActionScope.delivered?()
  end

  test "a failed action puts the view messages it took back ahead of those that arrived since" do
    reference = make_ref()
    send(self(), {reference, {:patch, "topic", %{to: "/first"}}})
    send(self(), {:fluffy_live_view, :watcher, {:redirect, :first}})

    assert_raise RuntimeError, fn ->
      ActionScope.run(fn ->
        assert_receive {^reference, {:patch, "topic", _options}} = patch
        ActionScope.record_taken(patch)
        assert_receive {:fluffy_live_view, :watcher, _event} = event
        ActionScope.record_taken(event)
        send(self(), {reference, {:patch, "topic", %{to: "/second"}}})
        send(self(), {:fluffy_live_view, :watcher, {:redirect, :second}})
        raise "failed"
      end)
    end

    {:messages, messages} = Process.info(self(), :messages)

    assert [%{to: "/first"}, %{to: "/second"}] = for({^reference, {:patch, _topic, options}} <- messages, do: options)
    assert [:first, :second] = for({:fluffy_live_view, :watcher, {:redirect, which}} <- messages, do: which)
  end
end
