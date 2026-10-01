defmodule Fluffy.TestWeb.CheckedControlsLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) and params["topic"] do
      Phoenix.PubSub.subscribe(Fluffy.TestPubSub, params["topic"])
    end

    {:ok, assign(socket, revision: 0, choice: "red")}
  end

  @impl true
  def handle_info(:choose_blue, socket) do
    {:noreply, assign(socket, revision: socket.assigns.revision + 1, choice: "blue")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Revision {@revision}</p>
      <label><input id="enabled" type="checkbox" /> Enabled</label>
      <label for="colour">Colour</label>
      <select id="colour">
        <option :for={colour <- ~w(red green blue)} value={colour} selected={@choice == colour}>
          {colour}
        </option>
      </select>
    </main>
    """
  end
end
