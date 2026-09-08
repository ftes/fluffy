defmodule Fluffy.TestScope do
  @moduledoc false

  use GenServer

  alias Ecto.Adapters.SQL.Sandbox
  alias Fluffy.Playwright.NavigationObserver
  alias Fluffy.Playwright.Trace
  alias PlaywrightEx.BrowserContext

  @process_key {__MODULE__, :current}

  @type attachment :: :unmanaged | {pid(), reference(), {String.t(), String.t()} | nil}

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
        {__MODULE__,
         owners: owners,
         sandbox_header: sandbox_header,
         test_context: test_context(context),
         timeout: Keyword.fetch!(options, :timeout)},
        id: make_ref()
      )

    put_current(scope)
    :ok
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  def child_spec(options) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary}
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
    session_id = make_ref()
    :ok = GenServer.call(scope, {:attach_session, session_id})
    {scope, session_id, GenServer.call(scope, :sandbox_header)}
  end

  def attachment_values(:unmanaged), do: {nil, nil, nil}
  def attachment_values({_scope, _session_id, _header} = attachment), do: attachment

  def register_browser_context(nil, _session_id, _context_id), do: :ok

  def register_browser_context(scope, session_id, context_id) do
    GenServer.call(scope, {:register, session_id, {:browser_context, context_id}})
  end

  def register_trace(scope, session_id, trace) do
    GenServer.call(scope, {:register, session_id, {:trace, trace}})
  end

  def register_navigation_observer(nil, _session_id, _observer), do: :ok

  def register_navigation_observer(scope, session_id, observer) do
    GenServer.call(scope, {:register, session_id, {:navigation_observer, observer}})
  end

  @doc false
  def release_navigation_observer(nil, _session_id, _observer), do: :ok

  def release_navigation_observer(scope, session_id, observer) do
    release_resource(scope, session_id, {:navigation_observer, observer})
  end

  def register_live_view(nil, _session_id, _view_pid), do: :ok

  def register_live_view(scope, session_id, view_pid) do
    GenServer.call(scope, {:register, session_id, {:live_view, view_pid}})
  end

  @doc false
  def release_live_view(nil, _session_id, _view_pid), do: :ok

  def release_live_view(scope, session_id, view_pid) do
    release_resource(scope, session_id, {:live_view, view_pid})
  end

  def register_upload_client(nil, _session_id, _upload_client_pid), do: :ok

  def register_upload_client(scope, session_id, upload_client_pid) do
    GenServer.call(scope, {:register, session_id, {:upload_client, upload_client_pid}})
  end

  @doc false
  def release_upload_client(nil, _session_id, _upload_client_pid), do: :ok

  def release_upload_client(scope, session_id, upload_client_pid) do
    release_resource(scope, session_id, {:upload_client, upload_client_pid})
  end

  defp release_resource(scope, session_id, resource) do
    if Process.alive?(scope) do
      try do
        GenServer.call(scope, {:release, session_id, resource}, :infinity)
      catch
        :exit, _reason -> :ok
      end
    else
      :ok
    end
  end

  def close_session(nil, _session_id), do: :not_managed

  def close_session(scope, session_id) do
    if Process.alive?(scope) do
      GenServer.call(scope, {:close_session, session_id}, :infinity)
    else
      :ok
    end
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
       test_context: Keyword.fetch!(options, :test_context),
       timeout: Keyword.get(options, :timeout, 5_000)
     }}
  end

  @impl true
  def handle_call({:attach_session, session_id}, _from, state) do
    {:reply, :ok, put_in(state, [:sessions, session_id], [])}
  end

  def handle_call(:sandbox_header, _from, state) do
    {:reply, state.sandbox_header, state}
  end

  def handle_call(:test_context, _from, state) do
    {:reply, state.test_context, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, Map.take(state, [:owners, :sandbox_header, :sessions, :test_context]), state}
  end

  def handle_call({:register, session_id, resource}, _from, state) do
    sessions = Map.update(state.sessions, session_id, [resource], &[resource | &1])
    {:reply, :ok, %{state | sessions: sessions}}
  end

  def handle_call({:close_session, session_id}, _from, state) do
    {resources, sessions} = Map.pop(state.sessions, session_id, [])
    cleanup_resources(resources, state.timeout)
    {:reply, :ok, %{state | sessions: sessions}}
  end

  def handle_call({:release, session_id, resource}, _from, state) do
    resources = Map.get(state.sessions, session_id, [])

    case List.delete(resources, resource) do
      ^resources ->
        {:reply, :ok, state}

      remaining ->
        {:reply, :ok, put_in(state, [:sessions, session_id], remaining)}
    end
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
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    state.sessions
    |> Map.values()
    |> List.flatten()
    |> cleanup_resources(state.timeout)

    Enum.each(state.owners, &stop_sandbox_owner/1)
    :ok
  end

  defp cleanup_resources(resources, timeout) do
    resources
    |> Enum.filter(&match?({:trace, _trace}, &1))
    |> Enum.each(fn {:trace, trace} -> safely(fn -> Trace.stop(trace) end) end)

    resources
    |> Enum.filter(&match?({:navigation_observer, _observer}, &1))
    |> Enum.each(fn {:navigation_observer, observer} ->
      safely(fn -> NavigationObserver.stop(observer) end)
    end)

    resources
    |> Enum.filter(&match?({:browser_context, _context_id}, &1))
    |> Enum.each(fn {:browser_context, context_id} ->
      safely(fn -> BrowserContext.close(context_id, timeout: timeout) end)
    end)

    resources
    |> Enum.filter(&match?({:upload_client, _upload_client_pid}, &1))
    |> Enum.each(fn {:upload_client, upload_client_pid} ->
      stop_process(upload_client_pid, timeout)
    end)

    resources
    |> Enum.filter(&match?({:live_view, _view_pid}, &1))
    |> Enum.each(fn {:live_view, view_pid} -> stop_process(view_pid, timeout) end)
  end

  defp stop_process(pid, timeout) do
    if Process.alive?(pid) do
      reference = Process.monitor(pid)
      Process.exit(pid, :shutdown)

      receive do
        {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
      after
        timeout ->
          if Process.alive?(pid), do: Process.exit(pid, :kill)

          receive do
            {:DOWN, ^reference, :process, ^pid, _reason} -> :ok
          after
            timeout -> :ok
          end
      end
    end
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
