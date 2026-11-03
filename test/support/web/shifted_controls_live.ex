defmodule Fluffy.TestWeb.ShiftedControlsLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, changed?: false)}

  @impl true
  def handle_event("change", _params, socket), do: {:noreply, assign(socket, changed?: true)}

  @impl true
  def render(assigns) do
    ~H"""
    <form id="shifted-controls" phx-change="change">
      <input :if={@changed?} type="text" name="note" aria-label="Note" />
      <input type="text" name="alpha" aria-label="Alpha" />
      <input
        type="text"
        name="patched"
        aria-label="Patched"
        value={if @changed?, do: "server"}
        phx-patch-focused
      />
      <select :if={@changed?} name="extra" aria-label="Extra"><option>x</option><option>y</option></select>
      <select name="first" aria-label="First"><option>x</option><option>y</option></select>
      <select name="second" aria-label="Second"><option>x</option><option>y</option></select>
    </form>
    <p>Changed: {@changed?}</p>
    """
  end
end
