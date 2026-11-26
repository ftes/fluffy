defmodule Fluffy.Support.Web.LumosLive do
  @moduledoc false

  use Phoenix.LiveView

  alias Fluffy.Support.Repo

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  # Runs once the browser is gone, as the test's sandbox owner is about to stop. Slow, so a
  # test that didn't wait for it would stop the owner first.
  @impl true
  def terminate(_reason, _socket) do
    Process.sleep(200)
    Repo.query!("INSERT INTO fluffy_records (value) VALUES ('Nox')")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <p>Lumos</p>
    """
  end
end

defmodule Fluffy.Support.Web.OwnSandboxHook do
  @moduledoc false

  # An application's own hook, Phoenix Ecto's example passing `Fluffy.Sandbox`. The static
  # render takes the endpoint plug's assign, so it allows the request process too.
  def on_mount(:default, _params, _session, socket) do
    socket =
      Phoenix.Component.assign_new(socket, :phoenix_ecto_sandbox, fn ->
        if Phoenix.LiveView.connected?(socket), do: Phoenix.LiveView.get_connect_info(socket, :user_agent)
      end)

    Phoenix.Ecto.SQL.Sandbox.allow(socket.assigns.phoenix_ecto_sandbox, Fluffy.Sandbox)
    {:cont, socket}
  end
end
