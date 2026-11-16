defmodule Fluffy.Support.Web.LabelClickLive do
  @moduledoc false

  use Phoenix.LiveView

  alias Phoenix.LiveView.JS

  # Logs every event in arrival order, so a test sees which events a click on a
  # label sends through its control.
  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, log: [], cloak?: false, owl?: false, wand?: false, house: nil, familiar?: false, banished?: false)}
  end

  @impl true
  def handle_event("clicked", params, socket), do: {:noreply, log(socket, "click:#{params["value"] || "-"}")}
  def handle_event("label", _params, socket), do: {:noreply, log(socket, "label")}
  def handle_event("pick", _params, socket), do: {:noreply, log(socket, "pick")}
  def handle_event("summon", _params, socket), do: {:noreply, log(socket, "summon")}
  def handle_event("sort", _params, socket), do: {:noreply, log(socket, "sort")}
  def handle_event("save", _params, socket), do: {:noreply, log(socket, "save")}
  def handle_event("mirror", %{"mirror" => mirror}, socket), do: {:noreply, log(socket, "mirror:#{mirror}")}
  def handle_event("adopt", _params, socket), do: {:noreply, socket |> assign(familiar?: true) |> log("adopt")}
  def handle_event("banish", _params, socket), do: {:noreply, socket |> assign(banished?: true) |> log("banish")}

  def handle_event("familiar", params, socket) do
    socket = assign(socket, familiar?: params["familiar"] == "yes")
    {:noreply, log(socket, "familiar:#{params["familiar"] || "-"},#{params["patronus"] || "-"}")}
  end

  def handle_event("change", params, socket) do
    socket =
      assign(socket,
        cloak?: params["cloak"] == "yes",
        owl?: params["owl"] == "yes",
        wand?: params["wand"] == "yes",
        house: params["house"]
      )

    {:noreply, log(socket, "change:#{Enum.map_join(~w(cloak owl wand house), ",", &(params[&1] || "-"))}")}
  end

  defp log(socket, entry), do: assign(socket, log: socket.assigns.log ++ [entry])

  @impl true
  def render(assigns) do
    ~H"""
    <form id="label-form" phx-change="change" phx-submit="save">
      <label>
        <input type="checkbox" name="cloak" value="yes" checked={@cloak?} phx-click="clicked" />
        <span>Invisibility cloak</span>
      </label>
      <label for="house-gryffindor">Gryffindor</label>
      <input
        id="house-gryffindor"
        type="radio"
        name="house"
        value="gryffindor"
        checked={@house == "gryffindor"}
      />
      <label for="owl" phx-click="label">Owl post</label>
      <input id="owl" type="checkbox" name="owl" value="yes" checked={@owl?} phx-click="clicked" />
      <div phx-click="pick">
        <label><input type="checkbox" name="wand" value="yes" checked={@wand?} /> Elder wand</label>
      </div>
      <a href="#" phx-click="sort">
        <label><input type="checkbox" name="hat" value="yes" /> Sorting hat</label>
      </a>
      <label for="summon">Accio</label>
      <button id="summon" type="button" phx-click="summon">Summon</button>
      <label for="save">Mischief managed</label>
      <button id="save">Save</button>
      <a href="#" phx-click={JS.toggle(to: "#spellbook")}>
        <label><input type="checkbox" name="broom" value="yes" /> Nimbus 2000</label>
      </a>
      <label for="lumos">Cast lumos</label>
      <a href="#" phx-click="sort"><button id="lumos">Lumos</button></a>
      <a href="#" phx-click="sort"><input id="quill" type="checkbox" name="quill" value="yes" /></a>
      <label for="quill">Quill</label>
    </form>
    <label for="mirror-b">
      <span>Mirror A</span> <output id="mirror-a" phx-click="mirror" phx-value-mirror="a">a</output>
    </label>
    <label for="mirror-a">
      <span>Mirror B</span> <output id="mirror-b" phx-click="mirror" phx-value-mirror="b">b</output>
    </label>
    <form id="familiar-form" phx-change="familiar">
      <label for="familiar" phx-click="adopt">Familiar</label>
      <input id="familiar" type="checkbox" name="familiar" value="yes" checked={@familiar?} />
      <label for="patronus" phx-click="banish">Patronus</label>
      <input
        :if={!@banished?}
        id="patronus"
        type="checkbox"
        name="patronus"
        value="yes"
        phx-click="clicked"
      />
    </form>
    <p id="spellbook">Spellbook</p>
    <p id="log">Log: {Enum.join(@log, " ")}</p>
    """
  end
end
