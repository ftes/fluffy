defmodule Fluffy.TestRepo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :fluffy,
    adapter: Ecto.Adapters.Postgres
end

defmodule Fluffy.TestRepoTwo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :fluffy,
    adapter: Ecto.Adapters.Postgres
end

defmodule Fluffy.TestDatabase do
  @moduledoc false

  use GenServer

  alias Ecto.Adapters.SQL.Sandbox

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
    start_repo(Fluffy.TestRepo)
    start_repo(Fluffy.TestRepoTwo)

    :ok = Sandbox.mode(Fluffy.TestRepo, :manual)
    :ok = Sandbox.mode(Fluffy.TestRepoTwo, :manual)
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
