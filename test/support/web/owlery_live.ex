defmodule Fluffy.Support.Web.OwleryLive do
  @moduledoc false

  # Counts the owls broadcast on `topic`, so a test decides when the page changes.
  use Phoenix.LiveView

  @impl true
  def mount(%{"topic" => topic}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Fluffy.TestPubSub, topic)
    {:ok, assign(socket, letters: 0, read?: false)}
  end

  @impl true
  def handle_info(:owl, socket), do: {:noreply, update(socket, :letters, &(&1 + 1))}

  @impl true
  def handle_event("read", _params, socket), do: {:noreply, assign(socket, :read?, true)}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p id="letters">Letters: {@letters}</p>
      <button :if={@letters > 0} type="button" phx-click="read">Read the letter</button>
      <fieldset :if={@letters > 0}>
        <input id="recipient" aria-label="Recipient" type="text" value="Harry" />
        <input id="sealed" aria-label="Sealed" type="checkbox" checked />
        <select id="supplies" aria-label="Supplies" multiple>
          <option selected value="wand">Wand</option>
          <option value="quill">Quill</option>
          <option selected value="robes">Robes</option>
        </select>
      </fieldset>
      <p :if={@read?}>You have been accepted at Hogwarts</p>
    </main>
    """
  end
end
