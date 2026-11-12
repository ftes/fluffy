defmodule Fluffy.Support.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :fluffy,
    adapter: Ecto.Adapters.Postgres
end

defmodule Fluffy.Support.RepoTwo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :fluffy,
    adapter: Ecto.Adapters.Postgres
end

defmodule Fluffy.Support.Database do
  @moduledoc false

  use GenServer

  alias Ecto.Adapters.SQL.Sandbox
  alias Fluffy.Support.Repo
  alias Fluffy.Support.RepoTwo

  def start_link(_options) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def ensure_started do
    GenServer.call(__MODULE__, :ensure_started, :infinity)
  end

  @impl true
  def init(:ok), do: {:ok, %{repo_started?: false}}

  @impl true
  def handle_call(:ensure_started, _from, %{repo_started?: false} = state) do
    start_repo(Repo)
    start_repo(RepoTwo)

    :ok = Sandbox.mode(Repo, :manual)
    :ok = Sandbox.mode(RepoTwo, :manual)
    {:reply, :ok, %{state | repo_started?: true}}
  end

  def handle_call(:ensure_started, _from, state) do
    {:reply, :ok, state}
  end

  defp start_repo(repo) do
    case DynamicSupervisor.start_child(Fluffy.TestServices, repo) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
