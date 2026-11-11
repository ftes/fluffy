defmodule Fluffy.TestWeb.TriggerOnConnectLive do
  @moduledoc false

  use Phoenix.LiveView

  # Hands the visitor to a controller as soon as the view connects, like a
  # login page continuing a redirect: only a controller can write the session.
  # `trigger=dead` sets the trigger on the dead render only, `trigger=loop`
  # triggers a form that comes back here, and `trigger=ministry` one that leaves
  # for another origin, like a sign-in at an identity provider. `then=navigate`
  # also navigates away right after the join, which the join's form beats.
  @impl true
  def mount(params, _session, socket) do
    trigger? =
      case params["trigger"] do
        "dead" -> not connected?(socket)
        _connected -> connected?(socket)
      end

    if connected?(socket) and params["then"] == "navigate", do: send(self(), :navigate)

    {method, action} =
      case params["trigger"] do
        "loop" -> {"get", "/live/trigger-on-connect"}
        "ministry" -> {"post", "https://ministry.example/floo"}
        _hand_off -> {"post", "/session/hand-off"}
      end

    {:ok,
     assign(socket,
       action: action,
       identity: params["identity"] || "anonymous",
       loop?: params["trigger"] == "loop",
       method: method,
       lit?: false,
       trigger?: trigger?
     )}
  end

  @impl true
  def handle_event("lumos", _params, socket), do: {:noreply, assign(socket, :lit?, true)}

  @impl true
  def handle_info(:navigate, socket), do: {:noreply, push_navigate(socket, to: "/live/secret-chamber")}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Floo powder for {@identity}</p>
      <button type="button" phx-click="lumos">Lumos</button>
      <p :if={@lit?}>Wand lit</p>
      <.form
        for={%{}}
        id="hand-off-form"
        method={@method}
        action={@action}
        phx-trigger-action={@trigger?}
      >
        <input type="hidden" name="identity" value={@identity} />
        <input :if={@loop?} type="hidden" name="trigger" value="loop" />
      </.form>
    </main>
    """
  end
end
