defmodule Fluffy.TestWeb.InitialConnectionLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    timezone = get_connect_params(socket)["timezone"] || "not supplied"
    {:ok, assign(socket, :timezone, timezone)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Live initial authorization accepted</p>
      <p>Live timezone: {@timezone}</p>
    </main>
    """
  end
end
