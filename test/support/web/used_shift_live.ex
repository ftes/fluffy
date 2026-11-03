defmodule Fluffy.TestWeb.UsedShiftLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, changed?: false, keys: [])}

  @impl true
  def handle_event("change", params, socket) do
    keys = params |> Map.keys() |> Enum.reject(&(&1 == "_target")) |> Enum.sort()
    {:noreply, assign(socket, changed?: true, keys: keys)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form id="used-shift" phx-change="change">
      <input :if={@changed?} type="text" name="note" aria-label="Note" />
      <input :for={v <- ~w(a b c)} type="radio" name="choice" value={v} aria-label={v} />
      <input type="text" name="other" aria-label="Other" />
    </form>
    <p>Changed: {@changed?}</p>
    <ul>
      <li :for={k <- @keys}>key:{k}</li>
    </ul>
    """
  end
end
