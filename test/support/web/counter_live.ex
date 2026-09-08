defmodule Fluffy.TestWeb.CounterLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  @impl true
  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Sleeping heads: {@count}</p>
      <button type="button" phx-click="increment">Play the flute</button>
    </main>
    """
  end
end
