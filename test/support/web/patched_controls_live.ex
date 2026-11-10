defmodule Fluffy.TestWeb.PatchedControlsLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, count: 0, page_title: "Controls")}

  @impl true
  def handle_event("bump", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}
  def handle_event("retitle", _params, socket), do: {:noreply, assign(socket, :page_title, "Retitled controls")}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <input name="note" aria-label="Note" />
      <button type="button" phx-click="bump">Bump</button>
      <button type="button" phx-click="retitle">Retitle</button>
      <p>Count: {@count}</p>
      <.live_component module={Fluffy.TestWeb.PatchedControlsComponent} id="patched-component" />
    </main>
    """
  end
end

defmodule Fluffy.TestWeb.PatchedControlsComponent do
  @moduledoc false

  use Phoenix.LiveComponent

  @impl true
  def mount(socket), do: {:ok, assign(socket, :count, 0)}

  @impl true
  def handle_event("bump", _params, socket), do: {:noreply, update(socket, :count, &(&1 + 1))}

  @impl true
  def render(assigns) do
    ~H"""
    <section>
      <input name="component_note" aria-label="Component note" />
      <button type="button" phx-click="bump" phx-target={@myself}>Bump component</button>
      <p>Component count: {@count}</p>
    </section>
    """
  end
end
