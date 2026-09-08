defmodule Fluffy.TestWeb.PageTitleLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Sealed chamber")}
  end

  @impl true
  def handle_event("change-title", _params, socket) do
    Process.send_after(self(), :change_title, 25)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:change_title, socket) do
    {:noreply, assign(socket, :page_title, "Revealed chamber")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <button type="button" phx-click="change-title">Change title</button>
    </main>
    """
  end
end
