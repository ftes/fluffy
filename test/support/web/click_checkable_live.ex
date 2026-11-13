defmodule Fluffy.Support.Web.ClickCheckableLive do
  @moduledoc false

  use Phoenix.LiveView

  # Logs every event in arrival order, so a test sees which events a click on a
  # checkbox or radio sends and in which order.
  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, log: [], agree?: false, notify?: false, size: nil)}
  end

  @impl true
  def handle_event("clicked", params, socket), do: {:noreply, log(socket, "click:#{params["value"] || "-"}")}

  def handle_event("change", params, socket) do
    socket = assign(socket, agree?: params["agree"] == "yes", size: params["size"])
    {:noreply, log(socket, "change:#{params["agree"] || "-"}/#{params["size"] || "-"}")}
  end

  def handle_event("notify-change", params, socket) do
    socket = assign(socket, notify?: params["notify"] == "yes")
    {:noreply, log(socket, "notify-change:#{params["notify"] || "-"}")}
  end

  defp log(socket, entry), do: assign(socket, log: socket.assigns.log ++ [entry])

  @impl true
  def render(assigns) do
    ~H"""
    <form id="checkable-form" phx-change="change">
      <input type="hidden" name="agree" value="no" />
      <label>
        <input type="checkbox" name="agree" value="yes" checked={@agree?} phx-click="clicked" /> Agree
      </label>
      <label :for={size <- ~w(s m)}>
        <input type="radio" name="size" value={size} checked={@size == size} phx-click="clicked" />
        Size {size}
      </label>
      <label>
        <input
          type="checkbox"
          name="notify"
          value="yes"
          checked={@notify?}
          phx-click="clicked"
          phx-change="notify-change"
        /> Notify
      </label>
    </form>
    <p id="log">Log: {Enum.join(@log, " ")}</p>
    """
  end
end
