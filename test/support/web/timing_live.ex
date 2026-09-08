defmodule Fluffy.TestWeb.TimingLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(%{"probe" => probe}, _session, socket) do
    {:ok, assign(socket, probe: probe, bare: "", numeric: "")}
  end

  @impl true
  def handle_event("changed", %{"timing" => timing}, socket) do
    Registry.dispatch(Fluffy.TestTimingProbe, socket.assigns.probe, fn entries ->
      Enum.each(entries, fn {pid, _value} ->
        send(pid, {:timing_change, socket.assigns.probe, timing})
      end)
    end)

    {:noreply,
     assign(socket,
       bare: Map.get(timing, "bare", socket.assigns.bare),
       numeric: Map.get(timing, "numeric", socket.assigns.numeric)
     )}
  end

  def handle_event("submitted", %{"timing" => timing}, socket) do
    Registry.dispatch(Fluffy.TestTimingProbe, socket.assigns.probe, fn entries ->
      Enum.each(entries, fn {pid, _value} ->
        send(pid, {:timing_submit, socket.assigns.probe, timing})
      end)
    end)

    {:noreply,
     assign(socket,
       bare: Map.get(timing, "bare", socket.assigns.bare),
       numeric: Map.get(timing, "numeric", socket.assigns.numeric)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form id="timing-form" phx-change="changed" phx-submit="submitted">
      <label>
        Bare debounce <input name="timing[bare]" value={@bare} phx-debounce />
      </label>
      <label>
        Numeric debounce <input name="timing[numeric]" value={@numeric} phx-debounce="25" />
      </label>
      <label>Throttled <input name="timing[throttled]" phx-throttle="1000" /></label>
      <label>Invalid throttle <input name="timing[invalid]" phx-throttle="later" /></label>
      <button>Save timing</button>
    </form>
    <p id="timing-value">{@bare}:{@numeric}</p>
    """
  end
end
