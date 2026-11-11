defmodule Fluffy.TestWeb.TriggerOnConnectLive do
  @moduledoc false

  use Phoenix.LiveView

  # Hands the visitor to a controller as soon as the view connects, like a
  # login page continuing a redirect: only a controller can write the session.
  # `trigger=dead` sets the trigger on the dead render only, `trigger=loop`
  # triggers a form that comes back here, and `trigger=ministry` one that leaves
  # for another origin, like a sign-in at an identity provider.
  @impl true
  def mount(params, _session, socket) do
    trigger? =
      case params["trigger"] do
        "dead" -> not connected?(socket)
        _connected -> connected?(socket)
      end

    {:ok,
     assign(socket,
       action: if(params["trigger"] == "ministry", do: "https://ministry.example/floo", else: "/session/hand-off"),
       identity: params["identity"] || "anonymous",
       loop?: params["trigger"] == "loop",
       lit?: false,
       trigger?: trigger?
     )}
  end

  @impl true
  def handle_event("lumos", _params, socket), do: {:noreply, assign(socket, :lit?, true)}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Floo powder for {@identity}</p>
      <button type="button" phx-click="lumos">Lumos</button>
      <p :if={@lit?}>Wand lit</p>
      <form
        :if={@loop?}
        id="loop-form"
        method="get"
        action="/live/trigger-on-connect"
        phx-trigger-action={@trigger?}
      >
        <input type="hidden" name="trigger" value="loop" />
      </form>
      <.form
        :if={!@loop?}
        for={%{}}
        id="hand-off-form"
        action={@action}
        phx-trigger-action={@trigger?}
      >
        <input type="hidden" name="identity" value={@identity} />
      </.form>
    </main>
    """
  end
end
