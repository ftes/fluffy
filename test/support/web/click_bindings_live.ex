defmodule Fluffy.Support.Web.ClickBindingsComponent do
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

defmodule Fluffy.Support.Web.ClickBindingsTargetComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  @impl true
  def handle_event("ping", _params, socket) do
    send(self(), {:log, "ping:#{socket.assigns.id}"})
    {:noreply, socket}
  end

  @impl true
  def render(assigns), do: ~H"<div id={@id}></div>"
end

defmodule Fluffy.Support.Web.ClickBindingsLive do
  @moduledoc false
  use Phoenix.LiveView

  alias Phoenix.LiveView.JS

  # Logs every event in arrival order, so a test sees which binding a click on
  # an element without its own phx-click reaches.
  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, log: [], tab: nil, name: "Rex")}

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, assign(socket, tab: params["tab"])}

  @impl true
  def handle_event("select", %{"name" => name}, socket), do: {:noreply, log(socket, "select:#{name}")}
  def handle_event("remove", %{"name" => name}, socket), do: {:noreply, log(socket, "remove:#{name}")}
  def handle_event("outer", _params, socket), do: {:noreply, log(socket, "outer")}
  def handle_event("save", _params, socket), do: {:noreply, log(socket, "save")}
  def handle_event("track", _params, socket), do: {:noreply, log(socket, "track")}
  def handle_event("pick-value", %{"value" => value}, socket), do: {:noreply, log(socket, "pick-value:#{value}")}
  def handle_event("rename", _params, socket), do: {:noreply, socket |> assign(name: "Fido") |> log("rename")}
  def handle_event("save-name", %{"name" => name}, socket), do: {:noreply, log(socket, "save-name:#{name}")}

  # Logs the whole payload, with each value's JSON type.
  def handle_event("inspect", params, socket) do
    payload = params |> Enum.sort() |> Enum.map_join(",", fn {name, value} -> "#{name}=#{inspect(value)}" end)
    {:noreply, log(socket, "inspect:#{payload}")}
  end

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
    <.live_component module={Fluffy.Support.Web.ClickBindingsComponent} id="click-bindings-component" />
    <div phx-click="outer">
      <form id="outer-form" phx-submit="save">
        <button type="submit">Save</button>
      </form>
    </div>
    <form id="inner-form" phx-submit="save">
      <button type="submit"><span>Save by text</span></button>
      <button type="submit" disabled><span>Save disabled</span></button>
    </form>
    <a href="/chamber"><span>Leave by text</span></a>
    <.link navigate="/live/secret-chamber"><span>Navigate by text</span></.link>
    <.link patch="/live/click-bindings?tab=two">
      <span phx-click="select" phx-value-name="patch">Patch by text</span>
    </.link>
    <a href="#" phx-click="track">Track here</a>
    <form id="tracked-form" phx-submit="save">
      <button phx-click="track">Track and save</button>
    </form>
    <a href="/chamber" phx-click="track">Track and leave</a>
    <.live_component module={Fluffy.Support.Web.ClickBindingsTargetComponent} id="target-a" />
    <.live_component module={Fluffy.Support.Web.ClickBindingsTargetComponent} id="target-b" />
    <button type="button" phx-target="#target-a" phx-click={JS.push("ping", target: "#target-b")}>Ping b</button>
    <input aria-label="Pick value" value="rendered" phx-click="pick-value" />
    <form id="rename-form" phx-submit="save-name">
      <input aria-label="Name" name="name" value={@name} />
      <button phx-click="rename">Rename and save</button>
    </form>
    <div id="valued-div" value="div-value" phx-click="inspect" phx-value-name="div">Inspect div</div>
    <ol>
      <li id="valued-item" value="3" phx-click="inspect">Inspect item</li>
    </ol>
    <input aria-label="Keyed" value="typed" phx-keydown="inspect" phx-value-key="custom" />
    <p id="log">Log: {Enum.join(@log, " ")}</p>
    <p id="tab">Tab: {@tab}</p>
    """
  end
end
