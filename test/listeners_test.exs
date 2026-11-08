defmodule Fluffy.Backend.Playwright.ListenersTest do
  use ExUnit.Case, async: true

  alias Fluffy.Backend.Playwright.Listeners

  # Like a PlaywrightEx emitter, removing a listener leaves a call of it that
  # already started running.
  defmodule Emitter do
    @moduledoc false
    def on(owner, event, listener), do: send(owner, {:registered, event, listener})
    def off(_owner, _event, _listener), do: :ok
  end

  test "a listener call still running after listening returns sends nothing" do
    listen = fn ref -> [{Emitter, self(), :event, fn value -> send(ref, {ref, value}) end}] end

    ref = Listeners.listening(listen, fn ref -> ref end)
    assert_received {:registered, :event, listener}

    test = self()

    spawn(fn ->
      listener.(:late)
      send(test, :called)
    end)

    assert_receive :called
    refute_received {^ref, _value}
  end
end
