defmodule Fluffy.TestWeb.ClickBindingsComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  @impl true
  def handle_event("pick", %{"name" => name}, socket) do
    send(self(), {:log, "component-pick:#{name}"})
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ul id="component-items">
      <li phx-click="pick" phx-value-name="gamma" phx-target={@myself}><span>Gamma</span></li>
    </ul>
    """
  end
end

defmodule Fluffy.TestWeb.ClickBindingsLive do
  @moduledoc false
  use Phoenix.LiveView

  # Logs every event in arrival order, so a test sees which binding a click on
  # an element without its own phx-click reaches.
  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, log: [], tab: nil)}

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, assign(socket, tab: params["tab"])}

  @impl true
  def handle_event("select", %{"name" => name}, socket), do: {:noreply, log(socket, "select:#{name}")}
  def handle_event("remove", %{"name" => name}, socket), do: {:noreply, log(socket, "remove:#{name}")}
  def handle_event("outer", _params, socket), do: {:noreply, log(socket, "outer")}
  def handle_event("save", _params, socket), do: {:noreply, log(socket, "save")}

  @impl true
  def handle_info({:log, entry}, socket), do: {:noreply, log(socket, entry)}

  defp log(socket, entry), do: assign(socket, log: socket.assigns.log ++ [entry])

  @impl true
  def render(assigns) do
    ~H"""
    <ul id="items">
      <li phx-click="select" phx-value-name="alpha"><span>Alpha</span></li>
      <li phx-click="select" phx-value-name="beta">
        <span>Beta</span>
        <button type="button" phx-click="remove" phx-value-name="beta">Remove beta</button>
      </li>
    </ul>
    <.live_component module={Fluffy.TestWeb.ClickBindingsComponent} id="click-bindings-component" />
    <div phx-click="outer">
      <form id="outer-form" phx-submit="save">
        <button type="submit">Save</button>
      </form>
    </div>
    <form id="inner-form" phx-submit="save">
      <button type="submit"><span>Save by text</span></button>
    </form>
    <a href="/chamber"><span>Leave by text</span></a>
    <.link navigate="/live/secret-chamber"><span>Navigate by text</span></.link>
    <.link patch="/live/click-bindings?tab=two">
      <span phx-click="select" phx-value-name="patch">Patch by text</span>
    </.link>
    <p id="log">Log: {Enum.join(@log, " ")}</p>
    <p id="tab">Tab: {@tab}</p>
    """
  end
end
