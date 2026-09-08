defmodule Fluffy.TestWeb.NavigationLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket) and params["async"] == "true" do
      Process.send_after(self(), :navigate, 30)
    end

    {:ok, assign(socket, step: params["step"] || "initial", topic: params["topic"])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :step, params["step"] || "initial")}
  end

  @impl true
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

  def handle_info(:patch, socket) do
    {:noreply, push_patch(socket, to: "/live/chamber-map?step=late-patched")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <p>Map position: {@step}</p>
      <.link patch="/live/chamber-map?step=patched">Reveal passage</.link>
      <.link navigate="/live/secret-chamber">Secret chamber</.link>
      <a :if={@topic} href={"/live/redirect-ready?topic=#{@topic}"} target="_blank">Open ready popup</a>
      <a href="/chamber">Sleeping chamber</a>
      <button type="button" phx-click="redirect_static">Lull guardian</button>
      <button type="button" phx-click="redirect_with_flash">Open secret passage</button>
      <button type="button" phx-click="navigate_after_event">Enter chamber after event</button>
      <button type="button" phx-click="patch_after_event">Reveal passage after event</button>
      <button :if={@topic} type="button" phx-click="navigate_ready">Navigate ready</button>
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
