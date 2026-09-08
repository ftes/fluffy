defmodule Fluffy.TestWeb.SessionLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket) do
    {:ok, assign(socket, :identity, session["identity"] || "anonymous")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Live identity: {@identity}</p>
      <a href="/session/show">Show static identity</a>
    </main>
    """
  end
end
