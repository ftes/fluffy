defmodule Fluffy.TestWeb.TriggerOnConnectLive do
  @moduledoc false

  use Phoenix.LiveView

  # Hands the visitor to a controller as soon as the view connects, like a
  # login page continuing a redirect: only a controller can write the session.
  # `trigger=dead` sets the trigger on the dead render only, and `trigger=loop`
  # triggers a form that comes back here.
  @impl true
  def mount(params, _session, socket) do
    trigger? =
      case params["trigger"] do
        "dead" -> not connected?(socket)
        _connected -> connected?(socket)
      end

    {:ok,
     assign(socket, identity: params["identity"] || "anonymous", loop?: params["trigger"] == "loop", trigger?: trigger?)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Handing off {@identity}</p>
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
        action="/session/hand-off"
        phx-trigger-action={@trigger?}
      >
        <input type="hidden" name="identity" value={@identity} />
      </.form>
    </main>
    """
  end
end
