defmodule Fluffy.TestWeb.NavigationLive do
  @moduledoc false

  use Phoenix.LiveView

  alias Phoenix.LiveView.JS

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) do
      case params["async"] do
        "true" -> Process.send_after(self(), :navigate, 30)
        "mount" -> send(self(), :navigate)
        "return" -> Process.send_after(self(), {:navigate, "/live/chamber-map?step=returned"}, 30)
        "return-late" -> Process.send_after(self(), {:navigate, "/live/chamber-map?step=returned&late=true"}, 30)
        "return-slow" -> Process.send_after(self(), {:navigate, "/live/chamber-map?late=true&reveal=150&delay=600"}, 30)
        "patch" -> Process.send_after(self(), :patch, 30)
        "patch-twice" -> Process.send_after(self(), :patch_twice, 30)
        _sync -> :ok
      end
    end

    # Connects slowly.
    if connected?(socket) and params["delay"], do: Process.sleep(String.to_integer(params["delay"]))

    # Renders the form a moment after connecting.
    late? = params["late"] == "true"

    if connected?(socket) and late?,
      do: Process.send_after(self(), :reveal, params |> Map.get("reveal", "40") |> String.to_integer())

    socket =
      assign(socket,
        late?: late?,
        step: params["step"] || "initial",
        topic: params["topic"],
        saved_step: nil,
        saves: 0
      )

    {:ok, mount_redirect(socket, connected?(socket) && params["redirect"])}
  end

  defp mount_redirect(socket, "live") do
    socket |> put_flash(:info, "The secret passage opened") |> push_navigate(to: "/live/secret-chamber")
  end

  defp mount_redirect(socket, "static"), do: redirect(socket, to: "/chamber")
  defp mount_redirect(socket, "ping"), do: push_navigate(socket, to: "/live/chamber-map?redirect=pong")
  defp mount_redirect(socket, "pong"), do: redirect(socket, to: "/live/chamber-map?redirect=ping")
  defp mount_redirect(socket, _none), do: socket

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :step, params["step"] || "initial")}
  end

  @impl true
  def handle_event("change_step", %{"step" => step}, socket) do
    {:noreply, push_patch(socket, to: "/live/chamber-map?#{URI.encode_query(%{step: step})}")}
  end

  def handle_event("save_step", %{"step" => step}, socket) do
    {:noreply, assign(socket, saved_step: step, saves: socket.assigns.saves + 1)}
  end

  def handle_event("redirect_static", _params, socket) do
    {:noreply, redirect(socket, to: "/chamber")}
  end

  def handle_event("redirect_with_flash", _params, socket) do
    socket = put_flash(socket, :info, "The secret passage opened")
    {:noreply, redirect(socket, to: "/live/secret-chamber")}
  end

  def handle_event("navigate_after_event", _params, socket) do
    send(self(), :navigate)
    {:noreply, socket}
  end

  def handle_event("patch_after_event", _params, socket) do
    Process.send_after(self(), :patch, 30)
    {:noreply, socket}
  end

  def handle_event("navigate_ready", _params, socket) do
    {:noreply, push_navigate(socket, to: "/live/redirect-ready?topic=#{socket.assigns.topic}")}
  end

  @impl true
  def handle_info(:navigate, socket) do
    {:noreply, push_navigate(socket, to: "/live/secret-chamber")}
  end

  def handle_info({:navigate, to}, socket) do
    {:noreply, push_navigate(socket, to: to)}
  end

  def handle_info(:reveal, socket), do: {:noreply, assign(socket, :late?, false)}

  def handle_info(:patch, socket) do
    {:noreply, push_patch(socket, to: "/live/chamber-map?step=late-patched")}
  end

  def handle_info(:patch_twice, socket) do
    send(self(), :patch)
    {:noreply, push_patch(socket, to: "/live/chamber-map?step=wandered")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Map position: {@step}</p>
      <form :if={!@late?} id="map-form" phx-change="change_step" phx-submit="save_step">
        <label for="map-step">Map step</label>
        <input id="map-step" name="step" value={@step} />
      </form>
      <label for="map-note">Map note</label>
      <input id="map-note" name="note" />
      <p :if={@saved_step}>Saved step: {@saved_step}</p>
      <p>Saves: {@saves}</p>
      <.link patch="/live/chamber-map?step=patched">Reveal passage</.link>
      <.link navigate="/live/secret-chamber">Secret chamber</.link>
      <.link navigate="/live/mounted-patch">Patching chamber</.link>
      <a :if={@topic} href={"/live/redirect-ready?topic=#{@topic}"} target="_blank">Open ready popup</a>
      <a href="/chamber">Sleeping chamber</a>
      <a href={"/chamber?from=#{@step}"}>Chamber from here</a>
      <button type="button" phx-click="redirect_static">Lull guardian</button>
      <button type="button" phx-click="redirect_with_flash">Open secret passage</button>
      <button type="button" phx-click="navigate_after_event">Enter chamber after event</button>
      <button type="button" phx-click="patch_after_event">Reveal passage after event</button>
      <button :if={@topic} type="button" phx-click="navigate_ready">Navigate ready</button>
      <label>
        <input
          type="checkbox"
          phx-click={
            JS.push("navigate_after_event")
            |> JS.push("save_step", value: %{step: "after-navigation"})
          }
        /> Enter chamber and save
      </label>
    </main>
    """
  end
end

defmodule Fluffy.TestWeb.DestinationLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>The secret chamber is open</p>
      <p :if={message = Phoenix.Flash.get(@flash, :info)}>{message}</p>
    </main>
    """
  end
end

defmodule Fluffy.TestWeb.MountedPatchLive do
  @moduledoc false

  use Phoenix.LiveView

  alias Phoenix.LiveView.JS

  @impl true
  def handle_params(params, _uri, socket), do: {:noreply, assign(socket, :step, params["step"] || "initial")}

  # The client patches as the view mounts, right after the redirect that joined it.
  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p phx-mounted={JS.patch("/live/mounted-patch?step=mounted")}>Patching chamber: {@step}</p>
    </main>
    """
  end
end
