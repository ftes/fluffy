defmodule Fluffy.TestWeb.ClockLive do
  @moduledoc false

  use Phoenix.LiveView

  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, spell: "none", rings: 0)}

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, assign(socket, :room, params["room"] || "hall")}

  @impl true
  def handle_event("cast", %{"spell" => spell}, socket), do: {:noreply, assign(socket, :spell, spell)}
  def handle_event("ring", _params, socket), do: {:noreply, update(socket, :rings, &(&1 + 1))}

  # The transition defers LiveView's DOM updates until its timer fires.
  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <form id="spell-form" phx-change="cast">
        <label>Spell <input name="spell" phx-debounce="500" /></label>
      </form>
      <p>Cast: {@spell}</p>
      <p>Rings: {@rings}</p>
      <p>Room: {@room}</p>
      <button type="button" phx-click="ring">Ring</button>
      <button type="button" phx-click={JS.transition("fade", time: 500) |> JS.push("ring")}>Fade</button>
      <.link patch="/live/clock?room=attic">Attic</.link>
      <.link navigate="/live/three-heads">Three heads</.link>
      <a href="/chamber">Chamber</a>
    </main>
    """
  end
end
