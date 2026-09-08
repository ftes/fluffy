defmodule Fluffy.LiveViewWatcher do
  @moduledoc false

  use GenServer, restart: :transient

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  @impl true
  def init(options) do
    caller = Keyword.fetch!(options, :caller)
    view = Keyword.fetch!(options, :view)
    reference = Process.monitor(view.pid)

    {:ok, %{caller: caller, reference: reference, view_pid: view.pid}}
  end

  @impl true
  def handle_info(
        {:DOWN, reference, :process, view_pid, reason},
        %{caller: caller, reference: reference, view_pid: view_pid} = state
      ) do
    event =
      case reason do
        {:shutdown, {kind, _data} = redirect} when kind in [:redirect, :live_redirect] ->
          {:redirect, redirect}

        _other ->
          {:died, reason}
      end

    send(caller, {:fluffy_live_view, self(), event})
    {:stop, :normal, state}
  end
end
