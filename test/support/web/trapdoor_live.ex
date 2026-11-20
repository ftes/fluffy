defmodule Fluffy.Support.Web.TrapdoorLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket), do: {:ok, assign(socket, :room, params["room"])}

  @impl true
  def render(%{room: "below"} = assigns) do
    ~H"""
    <main>Devil's Snare below the trapdoor</main>
    """
  end

  def render(assigns) do
    ~H"""
    <main>
      <p>Fluffy guards the trapdoor</p>
      <.link navigate="/live/trapdoor?room=below">Climb down</.link>
    </main>
    """
  end
end
