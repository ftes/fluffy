defmodule Fluffy.TestWeb.RadioShiftLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    {:ok, assign(socket, changed?: false, choice: nil, override: params["override"])}
  end

  @impl true
  def handle_event("change", params, socket) do
    {:noreply, assign(socket, changed?: true, choice: params["choice"])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form id="radio-shift" phx-change="change">
      <input :if={@changed? and is_nil(@override)} type="text" name="note" aria-label="Note" />
      <input
        :for={v <- ~w(a b c)}
        type="radio"
        name="choice"
        value={v}
        aria-label={v}
        checked={(@override && @choice && @override == v) || (is_nil(@override) && @choice == v)}
      />
      <input :for={v <- ~w(x y)} type="checkbox" name="extras[]" value={v} aria-label={v} />
    </form>
    <p>Changed: {@changed?}</p>
    <p>Choice: {@choice}</p>
    """
  end
end
