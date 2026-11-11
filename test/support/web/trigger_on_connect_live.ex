defmodule Fluffy.TestWeb.TriggerOnConnectLive do
  @moduledoc false

  use Phoenix.LiveView

  # Hands the visitor to a controller as soon as the view connects, like a
  # login page continuing a redirect: only a controller can write the session.
  # `trigger=dead` sets the trigger on the dead render only, `trigger=loop`
  # triggers a form that comes back here, and `trigger=ministry` one that leaves
  # for another origin, like a sign-in at an identity provider. `then=navigate`
  # also navigates away right after the join, which the join's form beats.
  # `trigger=later` leaves it to a render the server pushes after a button's.
  # `form=map` downloads a file, and `form=relative` posts to an action that
  # resolves only from the URL "Patch later" patches to.
  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) and params["then"] == "navigate", do: send(self(), :navigate)

    {method, action} =
      cond do
        params["trigger"] == "loop" -> {"get", "/live/trigger-on-connect"}
        params["trigger"] == "ministry" -> {"post", "https://ministry.example/floo"}
        params["form"] == "map" -> {"post", "/session/marauders-map"}
        params["form"] == "relative" -> {"post", "hand-off"}
        true -> {"post", "/session/hand-off"}
      end

    {:ok,
     assign(socket,
       action: action,
       identity: params["identity"] || "anonymous",
       lit?: false,
       loop?: params["trigger"] == "loop",
       method: method
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    trigger? =
      case params["trigger"] do
        "dead" -> not connected?(socket)
        "later" -> false
        _connected -> connected?(socket)
      end

    {:noreply, assign(socket, :trigger?, trigger?)}
  end

  @impl true
  def handle_event("lumos", _params, socket), do: {:noreply, assign(socket, :lit?, true)}

  def handle_event("trigger-later", _params, socket) do
    Process.send_after(self(), :trigger, 50)
    {:noreply, socket}
  end

  def handle_event("patch-later", _params, socket) do
    Process.send_after(self(), :patch, 50)
    {:noreply, socket}
  end

  @impl true
  def handle_info(:trigger, socket), do: {:noreply, assign(socket, :trigger?, true)}
  def handle_info(:navigate, socket), do: {:noreply, push_navigate(socket, to: "/live/secret-chamber")}

  # Patches to a URL whose handle_params sets the trigger. The view is busy
  # first, so a render Fluffy asks for meanwhile answers only after the patch.
  def handle_info(:patch, socket) do
    Process.sleep(100)
    to = "/live/trigger-on-connect/patched?identity=#{socket.assigns.identity}&form=relative"
    {:noreply, push_patch(socket, to: to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Floo powder for {@identity}</p>
      <button type="button" phx-click="lumos">Lumos</button>
      <p :if={@lit?}>Wand lit</p>
      <p :if={@trigger?}>I solemnly swear that I am up to no good</p>
      <button type="button" phx-click="trigger-later">Trigger later</button>
      <button type="button" phx-click="patch-later">Patch later</button>
      <.form
        for={%{}}
        id="trigger-form"
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
