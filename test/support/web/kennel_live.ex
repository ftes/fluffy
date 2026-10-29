defmodule Fluffy.TestWeb.KennelLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Fluffy's kennel",
       barks: [],
       tune: nil,
       treats: 0,
       treat_name: nil,
       bones: 0
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :yard, params["yard"] || "front")}
  end

  @impl true
  def handle_event("bark", %{"volume" => volume}, socket) do
    {:noreply, update(socket, :barks, &[volume | &1])}
  end

  def handle_event("whistle", %{"tune" => tune}, socket) do
    {:noreply, assign(socket, :tune, tune)}
  end

  def handle_event("rename", _params, socket) do
    {:noreply, assign(socket, :page_title, "Fluffy & friends")}
  end

  def handle_event("treat", _params, socket) do
    {:noreply, update(socket, :treats, &(&1 + 1))}
  end

  def handle_event("name-treat", %{"treat" => treat}, socket) do
    {:noreply, assign(socket, :treat_name, treat)}
  end

  def handle_event("bury-bone", _params, socket) do
    {:noreply, update(socket, :bones, &(&1 + 1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>Fluffy's kennel</h1>
      <p>Yard: {@yard}</p>
      <p>Barks: {Enum.join(@barks, ", ")}</p>
      <p>Tune: {@tune}</p>
      <button type="button" phx-click="rename">Rename kennel</button>
      <.portal id="treat-portal" target="#portal-root">
        <div id="treat-dialog" role="dialog" aria-label="Treats">
          <p>Treats: {@treats}</p>
          <button type="button" phx-click="treat">Give treat</button>
          <form phx-submit="name-treat">
            <input name="treat" aria-label="Treat name" />
            <button>Name treat</button>
          </form>
          <p>Treat name: {@treat_name}</p>
          <.portal id="bone-portal" target="body">
            <div id="bone-status" role="status" aria-label="Bones">
              <p>Bones: {@bones}</p>
              <button type="button" phx-click="bury-bone">Bury bone</button>
            </div>
          </.portal>
        </div>
      </.portal>
    </main>
    """
  end
end

defmodule Fluffy.TestWeb.KennelKitchenLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Kitchen")}

  @impl true
  def render(assigns) do
    ~H"""
    <main>
      <h1>Kennel kitchen</h1>
    </main>
    """
  end
end

defmodule Fluffy.TestWeb.KennelSidebarLive do
  @moduledoc false

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :naps, 0), layout: false}

  @impl true
  def handle_event("nap", _params, socket), do: {:noreply, update(socket, :naps, &(&1 + 1))}

  @impl true
  def render(assigns) do
    ~H"""
    <section aria-label="Sidebar">
      <p>Naps: {@naps}</p>
      <button type="button" phx-click="nap">Nap</button>
    </section>
    """
  end
end
