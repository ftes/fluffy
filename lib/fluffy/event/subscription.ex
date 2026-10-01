defmodule Fluffy.Event.Subscription do
  @moduledoc false
  use GenServer

  alias Fluffy.Deadline
  alias Fluffy.Session
  alias Fluffy.SessionRuntime

  def start(session, event, source, mode, handler, deadline) do
    options = {self(), session, event, source, mode, handler, deadline}
    start = if mode == :wait, do: &GenServer.start/3, else: &GenServer.start_link/3

    case start.(__MODULE__, options, []) do
      {:ok, pid} -> pid
      {:error, reason} -> raise "Could not register #{event.type} event: #{inspect(reason)}"
    end
  end

  def remove(pid) do
    GenServer.call(pid, :remove, :infinity)
  catch
    :exit, {:noproc, _} -> :ok
    :exit, {:normal, _} -> :ok
  end

  def cancel(pid) do
    GenServer.stop(pid, :normal, :infinity)
  catch
    :exit, {:noproc, _} -> :ok
    :exit, {:normal, _} -> :ok
  end

  @impl true
  def init({owner, session, event, source, mode, handler, deadline}) do
    Process.flag(:trap_exit, true)
    Process.monitor(owner)
    runtime_monitor = Process.monitor(session.runtime)
    {decode, unsubscribe} = Session.backend(session).subscribe_event(session, event.type, source, self())

    case SessionRuntime.subscribe(session.runtime, self(), source, event.type, handler) do
      :ok ->
        timer = if deadline, do: Process.send_after(self(), :timeout, Deadline.remaining(deadline))

        {:ok,
         %{
           runtime: session.runtime,
           runtime_monitor: runtime_monitor,
           event: event,
           mode: mode,
           handler: handler,
           decode: decode,
           unsubscribe: unsubscribe,
           deadline: deadline,
           timer: timer,
           outcome: nil,
           awaiting: nil,
           task: nil,
           queue: :queue.new()
         }}

      {:error, reason} ->
        unsubscribe.()
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:remove, _from, state) do
    state = release(state)

    if state.task,
      do: {:reply, :ok, %{state | mode: :removed, queue: :queue.new()}},
      else: {:stop, :normal, :ok, state}
  end

  def handle_call(:claim_once, _from, state), do: {:reply, :ok, release(state)}

  def handle_call(:await, from, %{mode: :wait, outcome: nil, awaiting: nil} = state),
    do: {:noreply, %{state | awaiting: from}}

  def handle_call(:await, _from, %{mode: :wait, outcome: outcome} = state) when not is_nil(outcome),
    do: {:stop, :normal, outcome, state}

  def handle_call(:await, _from, state), do: {:reply, {:error, "a pending event can only be awaited once"}, state}

  @impl true
  def handle_info({ref, result}, %{task: %Task{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    state = %{state | task: nil}

    if state.mode == :removed or result == :closed or (state.mode == :once and result == :handled),
      do: {:stop, :normal, state},
      else: next_handler(state)
  end

  def handle_info({:EXIT, pid, reason}, %{task: %Task{pid: pid}} = state), do: {:stop, reason, %{state | task: nil}}

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{runtime_monitor: ref} = state),
    do: fail(state, "session is closed")

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:stop, :normal, state}
  def handle_info({:source_closed, reason}, state), do: fail(state, reason)
  def handle_info(:timeout, state), do: fail(state, "no matching #{state.event.type} event occurred before the timeout")
  def handle_info(_message, %{outcome: outcome} = state) when not is_nil(outcome), do: {:noreply, state}

  def handle_info(message, state) do
    if state.deadline && Deadline.expired?(state.deadline) do
      fail(state, "no matching #{state.event.type} event occurred before the timeout")
    else
      deliver(message, state)
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.task, do: Task.shutdown(state.task, :brutal_kill)
    release(state)
  end

  defp deliver(message, %{mode: :wait} = state) do
    case candidate(message, state) do
      {:ok, value} -> settle(state, {:ok, value})
      :ignore -> {:noreply, state}
      {:error, reason} -> fail(state, reason)
    end
  catch
    kind, reason -> settle(state, {:raise, kind, reason, __STACKTRACE__})
  end

  defp deliver(message, state) do
    next_handler(%{state | queue: :queue.in(message, state.queue)})
  end

  defp next_handler(%{task: %Task{}} = state), do: {:noreply, state}

  defp next_handler(state) do
    case :queue.out(state.queue) do
      {:empty, _} ->
        {:noreply, state}

      {{:value, message}, queue} ->
        subscription = self()

        task = Task.async(fn -> run_handler(message, state, subscription) end)

        {:noreply, %{state | task: task, queue: queue}}
    end
  end

  defp run_handler(message, state, subscription) do
    case candidate(message, state) do
      {:ok, value} ->
        if state.mode == :once, do: GenServer.call(subscription, :claim_once, :infinity)
        state.handler.(value)
        :handled

      :ignore ->
        :ignored

      {:error, _reason} ->
        :closed
    end
  end

  defp candidate(message, state) do
    result =
      case message do
        {:fluffy_event, value} -> {:ok, value}
        _ -> state.decode.(message)
      end

    case result do
      {:ok, value} ->
        if is_nil(state.event.predicate) || state.event.predicate.(value), do: {:ok, value}, else: :ignore

      other ->
        other
    end
  end

  defp fail(%{outcome: outcome} = state, _reason) when not is_nil(outcome), do: {:noreply, state}
  defp fail(%{mode: :wait} = state, reason), do: settle(state, {:error, reason})
  defp fail(state, _reason), do: {:stop, :normal, state}

  defp settle(state, outcome) do
    state = release(state)

    if state.awaiting do
      GenServer.reply(state.awaiting, outcome)
      {:stop, :normal, state}
    else
      {:noreply, %{state | outcome: outcome}}
    end
  end

  defp release(%{unsubscribe: nil} = state), do: state

  defp release(state) do
    if state.timer, do: Process.cancel_timer(state.timer)
    state.unsubscribe.()
    SessionRuntime.unsubscribe(state.runtime, self())
    %{state | unsubscribe: nil, timer: nil}
  end
end
