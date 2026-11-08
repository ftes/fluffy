defmodule Fluffy.BrowserRuntime do
  @moduledoc false

  # Assigns each session to the least-loaded browser slot, ties to the lowest,
  # so that sequential sessions reuse one browser and only real concurrency
  # launches more. Assignment never waits: slots launch in their own processes.

  use GenServer

  alias __MODULE__.Slot

  defstruct [:timeout, slots: [], assignments: %{}]

  @opaque t :: %__MODULE__{
            timeout: timeout(),
            slots: [pid()],
            assignments: %{pid() => {pid(), reference()}}
          }

  @doc "Returns the calling process's browser, launching it if needed. Raises if it cannot launch."
  def browser(server \\ __MODULE__) do
    server |> assign() |> Slot.browser()
  end

  @doc "Returns a browser other than `lost` from the calling process's slot, launching one if `lost` is current."
  def replace(server \\ __MODULE__, lost) do
    server |> assign() |> Slot.replace(lost)
  end

  # A process that exits releases its slot without this. Releasing as a session
  # closes frees the slot for the very next session.
  @doc "Frees the calling process's slot."
  def release(server \\ __MODULE__) do
    GenServer.call(server, {:release, self()}, :infinity)
  end

  # Asks the slots from the caller, so a launching slot holds up only this call.
  def status(server \\ __MODULE__) do
    slots =
      for {slot, load} <- GenServer.call(server, :loads, :infinity),
          do: Map.merge(Slot.status(slot), %{pid: slot, load: load})

    %{
      browser: Enum.find_value(slots, & &1.browser),
      initialized?: Enum.any?(slots, & &1.browser),
      launch_count: slots |> Enum.map(& &1.launch_count) |> Enum.sum(),
      playwright_name: hd(slots).playwright_name,
      slots: slots
    }
  end

  defp assign(server), do: GenServer.call(server, {:assign, self()}, :infinity)

  def start_link(options) do
    name = Keyword.get(options, :name, __MODULE__)
    GenServer.start_link(__MODULE__, options, name: name)
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    slot_options = Keyword.drop(options, [:name, :pool_size])

    slots =
      for _slot <- 1..Keyword.get(options, :pool_size, 1) do
        {:ok, slot} = Slot.start_link(slot_options)
        slot
      end

    {:ok, %__MODULE__{timeout: Keyword.fetch!(options, :timeout), slots: slots}}
  end

  @impl true
  def handle_call({:assign, owner}, _from, state) do
    case state.assignments do
      %{^owner => {slot, _monitor}} ->
        {:reply, slot, state}

      assignments ->
        slot = least_loaded(state)
        assignment = {slot, Process.monitor(owner)}
        {:reply, slot, %{state | assignments: Map.put(assignments, owner, assignment)}}
    end
  end

  def handle_call({:release, owner}, _from, state) do
    {:reply, :ok, unassign(state, owner)}
  end

  def handle_call(:loads, _from, state) do
    loads = loads(state)
    {:reply, Enum.map(state.slots, &{&1, Map.get(loads, &1, 0)}), state}
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, owner, _reason}, state) do
    {:noreply, unassign(state, owner)}
  end

  def handle_info({:EXIT, slot, reason}, state) do
    if slot in state.slots, do: {:stop, reason, state}, else: {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  # Each slot closes its browser within the runtime's timeout, all at once.
  @impl true
  def terminate(_reason, state) do
    state.slots
    |> Enum.map(fn slot -> Task.async(fn -> stop_slot(slot) end) end)
    |> Task.yield_many(state.timeout)

    :ok
  end

  defp stop_slot(slot) do
    GenServer.stop(slot, :shutdown, :infinity)
  catch
    :exit, _reason -> :ok
  end

  defp least_loaded(state) do
    loads = loads(state)
    Enum.min_by(state.slots, &Map.get(loads, &1, 0))
  end

  defp loads(state) do
    Enum.frequencies_by(state.assignments, fn {_owner, {slot, _monitor}} -> slot end)
  end

  defp unassign(state, owner) do
    case Map.pop(state.assignments, owner) do
      {nil, _assignments} ->
        state

      {{_slot, monitor}, assignments} ->
        Process.demonitor(monitor, [:flush])
        %{state | assignments: assignments}
    end
  end
end
