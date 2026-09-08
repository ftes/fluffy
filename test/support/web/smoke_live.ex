defmodule Fluffy.TestWeb.SmokeLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :count, 0)}
  end

  @impl true
  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Guardian head count: {@count}</p>

      <section data-zone="primary">
        <button type="button" phx-click="increment">Rouse guardian head</button>
      </section>

      <section data-zone="secondary">
        <button type="button">Rouse guardian head</button>
      </section>

      <.live_component module={Fluffy.TestWeb.SmokeComponent} id="smoke-component" />
    </main>
    """
  end
end

defmodule Fluffy.TestWeb.SmokeComponent do
  @moduledoc false

  use Phoenix.LiveComponent

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign_new(:count, fn -> 0 end)}
  end

  @impl true
  def handle_event("increment", _params, socket) do
    {:noreply, update(socket, :count, &(&1 + 1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <p>Phoenix count: {@count}</p>
      <button type="button" phx-click="increment" phx-target={@myself}>
        Summon phoenix
      </button>
    </div>
    """
  end
end
