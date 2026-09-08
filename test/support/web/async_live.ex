defmodule Fluffy.TestWeb.AsyncLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    delay = params |> Map.get("delay", "40") |> String.to_integer()

    if connected?(socket) do
      Process.send_after(self(), :ready, delay)
    end

    {:ok, assign(socket, ready?: false, activated?: false)}
  end

  @impl true
  def handle_info(:ready, socket) do
    {:noreply, assign(socket, :ready?, true)}
  end

  @impl true
  def handle_event("activate", _params, socket) do
    {:noreply, assign(socket, :activated?, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Status: {if @ready?, do: "ready", else: "waiting"}</p>
      <p :if={@activated?}>Activated</p>
      <button :if={@ready?} type="button" phx-click="activate">Appeared</button>
    </main>
    """
  end
end
