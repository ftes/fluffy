defmodule Fluffy.Support.Web.PatchedControlsLive do
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
      <select name="pick" aria-label="Pick"><option>a</option><option>b</option></select>
      <select name="preset" aria-label="Preset">
        <option>a</option><option selected>b</option><option>c</option>
      </select>
      <select name="many" aria-label="Many" multiple>
        <option>a</option><option selected>b</option>
      </select>
      <button type="button" phx-click="bump">Bump</button>
      <button type="button" phx-click="retitle">Retitle</button>
      <p>Count: {@count}</p>
      <.live_component module={Fluffy.Support.Web.PatchedControlsComponent} id="patched-component" />
    </main>
    """
  end
end

defmodule Fluffy.Support.Web.PatchedControlsComponent do
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
      <.portal id="component-portal" target="body">
        <div>
          <input name="portal_note" aria-label="Portal note" />
          <output>{@count}</output>
        </div>
      </.portal>
    </section>
    """
  end
end
