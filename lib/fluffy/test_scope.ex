defmodule Fluffy.TestScope do
  @moduledoc false

  use GenServer

  alias Ecto.Adapters.SQL.Sandbox
  alias Fluffy.SessionRuntime

  @process_key {__MODULE__, :current}

  @type attachment :: {pid() | nil, pid(), {String.t(), String.t()} | nil}

  def setup(context, options) when is_map(context) and is_list(options) do
    case current() do
      scope when is_pid(scope) ->
        if Process.alive?(scope) do
          raise ArgumentError, "Fluffy.Test.setup has already been called for this test"
        else
          Process.delete(@process_key)
        end

      nil ->
        :ok
    end

    {owners, sandbox_header} = acquire_sandbox(Keyword.fetch!(options, :sandbox))

    {:ok, scope} =
      ExUnit.Callbacks.start_supervised(
        {__MODULE__, owners: owners, sandbox_header: sandbox_header, test_context: test_context(context)},
        id: make_ref()
      )

    put_current(scope)
    :ok
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary, shutdown: :infinity}
  end

  def current, do: Process.get(@process_key)
  def put_current(scope) when is_pid(scope), do: Process.put(@process_key, scope)
  def status(scope), do: GenServer.call(scope, :status)
  def metadata(scope), do: GenServer.call(scope, :test_context)

  def attach_session do
    scope = current!()
    attach_session(scope)
  end

  @doc false
  def attach_session(scope) when is_pid(scope) do
    GenServer.call(scope, {:attach_session, self()})
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)

    owners = Keyword.get(options, :owners, [])

    {:ok,
     %{
       owner_references: Map.new(owners, &{Process.monitor(&1), &1}),
       owners: owners,
       sandbox_header: Keyword.get(options, :sandbox_header),
       sessions: %{},
       test_context: Keyword.fetch!(options, :test_context)
     }}
  end

  @impl true
  def handle_call({:attach_session, owner}, _from, state) do
    {:ok, runtime} = SessionRuntime.start(owner, self())
    state = %{state | sessions: Map.put(state.sessions, runtime, Process.monitor(runtime))}
    {:reply, {self(), runtime, state.sandbox_header}, state}
  end

  def handle_call(:test_context, _from, state), do: {:reply, state.test_context, state}

  def handle_call(:status, _from, state) do
    {:reply, Map.take(state, [:owners, :sandbox_header, :sessions, :test_context]), state}
  end

  @impl true
  def handle_info({:DOWN, reference, :process, owner, reason}, state) do
    case state.owner_references do
      %{^reference => ^owner} ->
        state = %{
          state
          | owner_references: Map.delete(state.owner_references, reference),
            owners: List.delete(state.owners, owner)
        }

        {:stop, {:shutdown, {:sandbox_owner_down, reason}}, state}

      _other ->
        {:noreply, %{state | sessions: Map.delete(state.sessions, owner)}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    Enum.each(Map.keys(state.sessions), &SessionRuntime.close/1)
    Enum.each(state.owners, &stop_sandbox_owner/1)
    :ok
  end

  if Code.ensure_loaded?(Sandbox) do
    defp stop_sandbox_owner(owner) do
      if Process.alive?(owner) do
        safely(fn -> Sandbox.stop_owner(owner) end)
      end
    end
  else
    defp stop_sandbox_owner(_owner), do: :ok
  end

  defp safely(fun) do
    fun.()
  rescue
    _reason -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp current! do
    case current() do
      scope when is_pid(scope) ->
        if Process.alive?(scope) do
          scope
        else
          Process.delete(@process_key)

          raise ArgumentError,
                "call Fluffy.Test.setup(context) before Fluffy.start_session/1,2"
        end

      nil ->
        raise ArgumentError,
              "call Fluffy.Test.setup(context) before Fluffy.start_session/1,2"
    end
  end

  defp acquire_sandbox(false), do: {[], nil}

  defp acquire_sandbox({module, function, arguments}) do
    apply(module, function, arguments)
  end

  defp test_context(context) do
    Map.take(context, [:async, :file, :line, :module, :test])
  end
end
