defmodule Fluffy.TestWeb.PhoenixHTMLLinkLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       action: Map.fetch!(params, "action"),
       competing_action?: params["competing_action"] == "true"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <a
        data-method="delete"
        data-to={@action}
        data-csrf="live-csrf"
        phx-click={@competing_action? && "competing-action"}
      >
        <span id="live-delete-label">Delete from LiveView</span>
      </a>
    </main>
    """
  end
end
