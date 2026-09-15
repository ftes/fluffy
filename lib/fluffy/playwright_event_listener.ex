defmodule Fluffy.PlaywrightEventListener do
  @moduledoc false

  use GenServer

  alias Fluffy.Playwright.SubscriptionRegistry
  alias PlaywrightEx.EventWaiter

  def start_link(options) do
    options = Keyword.put(options, :owner, self())
    {:ok, listener} = GenServer.start_link(__MODULE__, options)

    case GenServer.call(listener, :ready, :infinity) do
      :ok ->
        {:ok, listener}

      {:error, _reason} = error ->
        stop(listener)
        error
    end
  end

  def await(listener), do: GenServer.call(listener, :await, :infinity)

  def stop(listener) do
    GenServer.stop(listener, :normal, :infinity)
  catch
    :exit, {reason, {GenServer, :stop, _}} when reason in [:noproc, :normal] -> :ok
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    options = Keyword.validate!(options, [:connection, :event, :filter, :guid, :handler, :owner, :subscription, :timeout])
    connection = Keyword.fetch!(options, :connection)
    guid = Keyword.fetch!(options, :guid)
    timeout = Keyword.fetch!(options, :timeout)
    subscription = Keyword.get(options, :subscription)
    owner_reference = Process.monitor(Keyword.fetch!(options, :owner))
    deadline = System.monotonic_time(:millisecond) + timeout

    if subscription, do: SubscriptionRegistry.acquire(guid, subscription, max(timeout, 1), connection)

    listener = self()

    # The worker handles blocking dialogs while the caller is still in its action.
    # EventWaiter owns event selection, the deadline, and protocol lifecycle errors.
    task = Task.async(fn -> capture(listener, options, deadline) end)

    {:ok,
     %{
       connection: connection,
       guid: guid,
       subscription: subscription,
       timeout: timeout,
       owner_reference: owner_reference,
       task: task,
       ready: nil,
       ready_from: nil,
       result: nil,
       await_from: nil
     }}
  end

  @impl true
  def handle_call(:ready, from, %{ready: nil} = state), do: {:noreply, %{state | ready_from: from}}
  def handle_call(:ready, _from, state), do: {:reply, state.ready, state}
  def handle_call(:await, from, %{result: nil} = state), do: {:noreply, %{state | await_from: from}}
  def handle_call(:await, _from, state), do: {:reply, state.result, state}

  @impl true
  def handle_info({:armed, result}, state) do
    if state.ready_from, do: GenServer.reply(state.ready_from, result)
    {:noreply, %{state | ready: result, ready_from: nil}}
  end

  def handle_info({reference, result}, %{task: %Task{ref: reference}} = state) do
    Process.demonitor(reference, [:flush])
    if state.await_from, do: GenServer.reply(state.await_from, result)
    {:noreply, %{state | result: result, await_from: nil}}
  end

  def handle_info({:DOWN, reference, :process, _owner, _reason}, %{owner_reference: reference} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  def handle_info({:DOWN, reference, :process, _pid, reason}, %{task: %Task{ref: reference}} = state),
    do: {:stop, reason, state}

  @impl true
  def terminate(_reason, state) do
    Task.shutdown(state.task, :brutal_kill)

    if state.subscription,
      do: SubscriptionRegistry.release(state.guid, state.subscription, max(state.timeout, 1), state.connection)

    :ok
  end

  defp capture(listener, options, deadline) do
    result =
      EventWaiter.arm(Keyword.fetch!(options, :guid), Keyword.fetch!(options, :event),
        connection: Keyword.fetch!(options, :connection),
        predicate: Keyword.get(options, :filter, fn _event -> true end),
        timeout: max(deadline - System.monotonic_time(:millisecond), 0)
      )

    case result do
      {:ok, waiter} ->
        send(listener, {:armed, :ok})
        with {:ok, event} <- EventWaiter.await(waiter), do: handle_event(options[:handler], event)

      {:error, _reason} = error ->
        send(listener, {:armed, error})
        error
    end
  end

  defp handle_event(nil, event), do: {:ok, event}
  defp handle_event(handler, event), do: handler.(event)
end
