defmodule Fluffy.Playwright.SubscriptionRegistry do
  @moduledoc false

  use GenServer

  alias PlaywrightEx.Page, as: BrowserPage
  alias PlaywrightEx.Supervisor.Connection

  def start_link(_options), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def acquire(guid, event, timeout, connection \\ Connection) do
    GenServer.call(__MODULE__, {:acquire, connection, guid, event, timeout}, :infinity)
  end

  def release(guid, event, timeout, connection \\ Connection) do
    GenServer.call(__MODULE__, {:release, connection, guid, event, timeout}, :infinity)
  catch
    :exit, {reason, {GenServer, :call, _}} when reason in [:noproc, :normal, :shutdown] -> :ok
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:acquire, connection, guid, event, timeout}, _from, state) do
    key = {connection, guid, event}

    state =
      case Map.get(state, key, 0) do
        0 ->
          :ok = update_subscription!(connection, guid, event, true, timeout)
          Map.put(state, key, 1)

        count ->
          Map.put(state, key, count + 1)
      end

    {:reply, :ok, state}
  end

  def handle_call({:release, connection, guid, event, timeout}, _from, state) do
    key = {connection, guid, event}

    state =
      case Map.get(state, key, 0) do
        count when count <= 1 ->
          _result = update_subscription(connection, guid, event, false, timeout)
          Map.delete(state, key)

        count ->
          Map.put(state, key, count - 1)
      end

    {:reply, :ok, state}
  end

  defp update_subscription!(connection, guid, event, enabled, timeout) do
    case update_subscription(connection, guid, event, enabled, timeout) do
      {:ok, _result} -> :ok
      {:error, error} -> raise "could not enable Playwright #{event} events: #{inspect(error)}"
    end
  end

  defp update_subscription(connection, guid, event, enabled, timeout) do
    BrowserPage.update_subscription(guid, connection: connection, event: event, enabled: enabled, timeout: timeout)
  end
end
