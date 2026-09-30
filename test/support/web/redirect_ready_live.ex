defmodule Fluffy.TestWeb.RedirectReadyLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(:not_mounted_at_router, session, socket), do: mount(session, %{}, socket)

  def mount(%{"topic" => topic} = params, _session, socket) do
    if connected?(socket) do
      if params["delay"], do: Process.sleep(params["delay"])
      Phoenix.PubSub.subscribe(Fluffy.TestPubSub, topic)
    end

    {:ok, assign(socket, topic: topic, message: nil)}
  end

  @impl true
  def handle_info({:redirect_ready, message}, socket) do
    {:noreply, assign(socket, :message, message)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Redirect-ready LiveView</p>
      <p :if={@message}>Broadcast: {@message}</p>
    </main>
    """
  end
end
