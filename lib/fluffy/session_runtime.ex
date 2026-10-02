defmodule Fluffy.SessionRuntime do
  @moduledoc false
  use GenServer

  alias Fluffy.Page

  def start(owner, scope \\ nil) do
    DynamicSupervisor.start_child(__MODULE__.Supervisor, {__MODULE__, owner: owner, scope: scope})
  end

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  def child_spec(options),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [options]}, restart: :temporary, shutdown: :infinity}

  def configuration(runtime), do: call(runtime, :configuration)
  def backend(runtime), do: call(runtime, :backend)
  def context(runtime), do: call(runtime, :context)
  def put_context(runtime, context), do: call(runtime, {:context, context})
  def pages(runtime), do: call(runtime, :pages)
  def page(runtime, id), do: call(runtime, {:page, id})
  def external_page(runtime, id), do: call(runtime, {:external_page, id})
  def put_page_state(runtime, id, state), do: call(runtime, {:page_state, id, state})
  def replace_page(runtime, %Page.State{} = page), do: call(runtime, {:replace_page, page})
  def close_page(runtime, id), do: call(runtime, {:close_page, id})
  def resources(runtime), do: call(runtime, :resources)

  def register(runtime, resource, cleanup) when is_function(cleanup, 0),
    do: call(runtime, {:register_resource, resource, cleanup})

  def release(runtime, resource), do: call(runtime, {:release_resource, resource})
  def monitor(runtime, pid), do: call(runtime, {:monitor, pid})

  def subscribe(runtime, pid, source, type, handler), do: call(runtime, {:subscribe, pid, source, type, handler})
  def unsubscribe(runtime, pid), do: call(runtime, {:unsubscribe, pid})
  def remove_listener(runtime, source, type, handler), do: call(runtime, {:remove_listener, source, type, handler})
  def emit_event(runtime, source, type, value), do: call(runtime, {:event, source, type, value})

  def close(runtime) do
    GenServer.stop(runtime, :normal, :infinity)
  catch
    :exit, {:noproc, _} -> :ok
    :exit, {:normal, _} -> :ok
  end

  def resolve(runtime, %Page{runtime: runtime, id: id}) do
    with {:ok, _page} <- page(runtime, id), do: {:ok, id}
  end

  def resolve(_runtime, %Page{}), do: {:error, "page belongs to a different session"}

  def initialize(runtime, backend, context, page) do
    call(runtime, {:initialize, backend, context, page})
  end

  def register_page(runtime, %Page.State{} = page) do
    call(runtime, {:register_page, page})
  end

  defp call(runtime, message) do
    GenServer.call(runtime, message, :infinity)
  catch
    :exit, {:noproc, _} -> {:error, "session is closed"}
    :exit, {:normal, _} -> {:error, "session is closed"}
  end

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    owner = Keyword.fetch!(options, :owner)
    scope = Keyword.get(options, :scope)
    monitors = [Process.monitor(owner)] ++ if(scope, do: [Process.monitor(scope)], else: [])

    {:ok,
     %{
       backend: nil,
       context: nil,
       pages: %{},
       external_pages: %{},
       resources: [],
       subscriptions: [],
       monitors: monitors
     }}
  end

  @impl true
  def handle_call(:configuration, _from, state), do: {:reply, {:ok, {state.backend, state.context}}, state}
  def handle_call(:backend, _from, state), do: {:reply, {:ok, state.backend}, state}
  def handle_call(:context, _from, state), do: {:reply, {:ok, state.context}, state}
  def handle_call({:context, context}, _from, state), do: {:reply, :ok, %{state | context: context}}
  def handle_call(:pages, _from, state), do: {:reply, {:ok, state.pages}, state}

  def handle_call({:page, id}, _from, state), do: {:reply, fetch_page(state, id), state}
  def handle_call({:external_page, id}, _from, state), do: {:reply, {:ok, state.external_pages[id]}, state}

  def handle_call({:page_state, id, page_state}, _from, state) do
    case fetch_page(state, id) do
      {:ok, page} -> {:reply, :ok, %{state | pages: Map.put(state.pages, id, %{page | state: page_state})}}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:replace_page, page}, _from, state) do
    case fetch_page(state, page.id) do
      {:ok, _previous} -> {:reply, :ok, %{state | pages: Map.put(state.pages, page.id, page)}}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:close_page, id}, _from, state), do: {:reply, :ok, remove_page(state, id)}

  def handle_call({:initialize, backend, context, page}, _from, %{backend: nil} = state) do
    case backend.prepare_page(context, page) do
      {:ok, registration} -> register_page_reply(%{state | backend: backend, context: context}, registration)
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:initialize, _backend, _context, _registration}, _from, state),
    do: {:reply, {:error, "session is already initialized"}, state}

  def handle_call({:register_page, page}, _from, state) do
    case state.backend.prepare_page(state.context, page) do
      {:ok, registration} -> register_page_reply(state, registration)
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:resources, _from, state),
    do: {:reply, {:ok, Enum.map(state.resources, fn {resource, _cleanup} -> resource end)}, state}

  def handle_call({:register_resource, resource, cleanup}, _from, state),
    do: {:reply, :ok, %{state | resources: [{resource, cleanup} | state.resources]}}

  def handle_call({:release_resource, resource}, _from, state),
    do: {:reply, :ok, %{state | resources: List.keydelete(state.resources, resource, 0)}}

  def handle_call({:monitor, pid}, _from, state),
    do: {:reply, :ok, %{state | monitors: [Process.monitor(pid) | state.monitors]}}

  def handle_call({:subscribe, pid, source, type, handler}, _from, state) do
    if source == :context or Map.has_key?(state.pages, source) do
      subscription = %{pid: pid, source: source, type: type, handler: handler, monitor: Process.monitor(pid)}
      {:reply, :ok, %{state | subscriptions: [subscription | state.subscriptions]}}
    else
      {:reply, {:error, "event source page is closed"}, state}
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, remove_subscriptions(state, &(&1.pid == pid))}
  end

  def handle_call({:remove_listener, source, type, handler}, _from, state) do
    subscription = Enum.find(state.subscriptions, &(&1.source == source and &1.type == type and &1.handler == handler))

    if subscription do
      {:reply, {:ok, subscription.pid}, remove_subscriptions(state, &(&1.pid == subscription.pid))}
    else
      {:reply, {:ok, nil}, state}
    end
  end

  def handle_call({:event, source, type, value}, _from, state) do
    for subscription <- state.subscriptions,
        subscription.source == source and subscription.type == type,
        do: send(subscription.pid, {:fluffy_event, value})

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if ref in state.monitors,
      do: {:stop, :normal, state},
      else: {:noreply, remove_subscriptions(state, &(&1.monitor == ref))}
  end

  def handle_info(_message, %{backend: nil} = state), do: {:noreply, state}

  def handle_info(message, state) do
    case state.backend.runtime_event(state.context, message) do
      {:page_opened, registration} ->
        case put_page(state, registration) do
          {:ok, _id, updated} -> {:noreply, updated}
          {:error, _reason} -> {:noreply, state}
        end

      {:page_closed, key} ->
        {:noreply, remove_page(state, state.external_pages[key])}

      :closed ->
        {:stop, :normal, state}

      :ignore ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Resources unwind in reverse acquisition order, including partial startup.
    for {_resource, cleanup} <- state.resources, do: safely(cleanup)
    :ok
  end

  defp fetch_page(state, id) do
    case Map.fetch(state.pages, id) do
      {:ok, page} -> {:ok, page}
      :error -> {:error, "page #{inspect(id)} is closed"}
    end
  end

  defp register_page_reply(state, registration) do
    case put_page(state, registration) do
      {:ok, id, updated} -> {:reply, {:ok, id}, updated}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp put_page(state, {page, external_id, opener_id}) do
    existing = if external_id, do: state.external_pages[external_id]

    if existing do
      {:ok, existing, state}
    else
      store_page(state, page, external_id, opener_id)
    end
  end

  defp store_page(state, page, external_id, opener_id) do
    id = make_ref()

    with :ok <- state.backend.subscribe_page(state.context, page, self()) do
      opener = if opener_id, do: state.external_pages[opener_id], else: page.opener
      page = %{page | id: id, opener: if(Map.has_key?(state.pages, opener), do: opener)}
      state = %{state | pages: Map.put(state.pages, id, page)}
      state = if external_id, do: %{state | external_pages: Map.put(state.external_pages, external_id, id)}, else: state
      {:ok, id, state}
    end
  end

  defp remove_page(state, id) do
    {page, pages} = Map.pop(state.pages, id)

    if page do
      for subscription <- state.subscriptions,
          subscription.source == id,
          do: send(subscription.pid, {:source_closed, "event source page is closed"})

      # Like Playwright, a live page has no opener once that opener closes.
      pages = Map.new(pages, fn {key, page} -> {key, if(page.opener == id, do: %{page | opener: nil}, else: page)} end)
      %{state | pages: pages}
    else
      state
    end
  end

  defp remove_subscriptions(state, predicate) do
    {removed, kept} = Enum.split_with(state.subscriptions, predicate)
    for subscription <- removed, do: Process.demonitor(subscription.monitor, [:flush])
    %{state | subscriptions: kept}
  end

  defp safely(fun) do
    fun.()
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end
end
