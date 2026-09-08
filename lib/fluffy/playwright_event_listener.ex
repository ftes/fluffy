defmodule Fluffy.PlaywrightEventListener do
  @moduledoc false

  use GenServer

  alias Fluffy.Playwright.SubscriptionRegistry
  alias PlaywrightEx.Connection

  def start_link(options) do
    GenServer.start_link(__MODULE__, Keyword.put_new(options, :owner, self()))
  end

  def await(listener, timeout) do
    GenServer.call(listener, {:await, timeout}, :infinity)
  end

  def stop(listener) do
    if Process.alive?(listener), do: GenServer.stop(listener, :normal, :infinity)
    :ok
  catch
    :exit, _reason -> :ok
  end

  @impl true
  def init(options) do
    options =
      Keyword.validate!(options, [
        :filter,
        :guid,
        :handler,
        :owner,
        :subscription,
        :timeout
      ])

    guid = Keyword.fetch!(options, :guid)
    owner = Keyword.fetch!(options, :owner)
    timeout = Keyword.fetch!(options, :timeout)
    subscription = Keyword.get(options, :subscription)
    owner_reference = Process.monitor(owner)

    :ok = PlaywrightEx.subscribe(guid, pid: self())
    enable_subscription!(guid, subscription, timeout)

    # The subscription call and this initializer call reach the same
    # Connection process from this process in order. The latter is the barrier
    # that makes listener-before-action deterministic.
    _initializer = Connection.initializer!(PlaywrightEx.Supervisor.Connection, guid)

    {:ok,
     %{
       event: nil,
       filter: Keyword.fetch!(options, :filter),
       guid: guid,
       handler: Keyword.get(options, :handler),
       owner: owner,
       owner_reference: owner_reference,
       subscription: subscription,
       timeout: timeout,
       timer: nil,
       waiter: nil
     }}
  end

  @impl true
  def handle_call({:await, _timeout}, _from, %{event: event} = state) when not is_nil(event) do
    {:reply, event, %{state | event: nil}}
  end

  def handle_call({:await, timeout}, from, %{waiter: nil} = state) do
    timer = Process.send_after(self(), :await_timeout, timeout)
    {:noreply, %{state | timer: timer, waiter: from}}
  end

  def handle_call({:await, _timeout}, _from, state) do
    {:reply, {:error, :already_waiting}, state}
  end

  @impl true
  def handle_info(
        {:DOWN, owner_reference, :process, owner, _reason},
        %{owner: owner, owner_reference: owner_reference} = state
      ) do
    {:stop, :normal, state}
  end

  def handle_info({:playwright_msg, event}, state) do
    case filter_event(state.filter, event) do
      {:ok, true} -> record(handle_event(state.handler, event), state)
      {:ok, false} -> {:noreply, state}
      {:ok, other} -> record({:error, {:invalid_event_filter_result, other}}, state)
      {:error, reason} -> record({:error, reason}, state)
    end
  end

  def handle_info(:await_timeout, %{waiter: nil} = state), do: {:noreply, state}

  def handle_info(:await_timeout, %{waiter: waiter} = state) do
    GenServer.reply(waiter, {:error, :timeout})
    {:noreply, %{state | timer: nil, waiter: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    disable_subscription(state.guid, state.subscription, state.timeout)
    PlaywrightEx.unsubscribe(state.guid, pid: self())
    :ok
  end

  defp record(result, %{waiter: nil} = state) do
    {:noreply, %{state | event: result}}
  end

  defp record(result, %{waiter: waiter, timer: timer} = state) do
    if timer, do: Process.cancel_timer(timer)
    GenServer.reply(waiter, result)
    {:noreply, %{state | timer: nil, waiter: nil}}
  end

  defp handle_event(nil, event), do: {:ok, event}

  defp handle_event(handler, event) do
    case handler.(event) do
      :ok -> {:ok, event}
      {:ok, value} -> {:ok, value}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_event_handler_result, other}}
    end
  rescue
    error -> {:error, {error, __STACKTRACE__}}
  end

  defp filter_event(filter, event) do
    {:ok, filter.(event)}
  rescue
    error -> {:error, {error, __STACKTRACE__}}
  end

  defp enable_subscription!(_guid, nil, _timeout), do: :ok

  defp enable_subscription!(guid, event, timeout) do
    SubscriptionRegistry.acquire(guid, event, timeout)
  end

  defp disable_subscription(_guid, nil, _timeout), do: :ok

  defp disable_subscription(guid, event, timeout) do
    SubscriptionRegistry.release(guid, event, timeout)
  end
end
