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

  # An application's own hook, passing `Fluffy.Sandbox` to Phoenix Ecto.
  def on_mount(:default, _params, _session, socket) do
    if Phoenix.LiveView.connected?(socket) do
      socket
      |> Phoenix.LiveView.get_connect_info(:user_agent)
      |> Phoenix.Ecto.SQL.Sandbox.allow(Fluffy.Sandbox)
    end

    {:cont, socket}
  end
end
