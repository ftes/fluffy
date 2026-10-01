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
  def page_names(runtime), do: call(runtime, :page_names)
  def page(runtime, id), do: call(runtime, {:page, id})
  def put_page_state(runtime, id, state), do: call(runtime, {:page_state, id, state})
  def replace_page(runtime, %Page.State{} = page), do: call(runtime, {:replace_page, page})
  def close_page(runtime, id), do: call(runtime, {:close_page, id})
  def resources(runtime), do: call(runtime, :resources)

  def register(runtime, resource, cleanup) when is_function(cleanup, 0),
    do: call(runtime, {:register_resource, resource, cleanup})

  def release(runtime, resource), do: call(runtime, {:release_resource, resource})
  def monitor(runtime, pid), do: call(runtime, {:monitor, pid})

  def begin_capture(runtime, type, key, options), do: call(runtime, {:begin_capture, type, key, options})
  def pending_capture(runtime), do: call(runtime, :pending_capture)
  def record_capture(runtime, token, value), do: call(runtime, {:record_capture, token, value})
  def finish_capture(runtime, token, value), do: call(runtime, {:finish_capture, token, value})
  def cancel_capture(runtime, token), do: call(runtime, {:cancel_capture, token})
  def fetch_result(runtime, key, type), do: call(runtime, {:fetch_result, key, type})

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
  def resolve(runtime, name), do: call(runtime, {:resolve, name})

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
       names: %{},
       external_pages: %{},
       resources: [],
       pending_capture: nil,
       results: %{},
       monitors: monitors
     }}
  end

  @impl true
  def handle_call(:configuration, _from, state), do: {:reply, {:ok, {state.backend, state.context}}, state}
  def handle_call(:backend, _from, state), do: {:reply, {:ok, state.backend}, state}
  def handle_call(:context, _from, state), do: {:reply, {:ok, state.context}, state}
  def handle_call({:context, context}, _from, state), do: {:reply, :ok, %{state | context: context}}
  def handle_call(:page_names, _from, state), do: {:reply, {:ok, Map.keys(state.names)}, state}

  def handle_call(:pages, _from, state) do
    pages = Map.new(state.pages, fn {_id, page} -> {page.name || page.id, page} end)
    {:reply, {:ok, pages}, state}
  end

  def handle_call({:page, id}, _from, state), do: {:reply, fetch_page(state, id), state}

  def handle_call({:resolve, name}, _from, state) do
    result =
      cond do
        Map.has_key?(state.pages, name) -> {:ok, name}
        Map.has_key?(state.names, name) -> {:ok, Map.fetch!(state.names, name)}
        true -> {:error, "no page named #{inspect(name)} exists in this session"}
      end

    {:reply, result, state}
  end

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
    case backend.prepare_page(context, page, self()) do
      {:ok, registration} -> register_page_reply(%{state | backend: backend, context: context}, registration)
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:initialize, _backend, _context, _registration}, _from, state),
    do: {:reply, {:error, "session is already initialized"}, state}

  def handle_call({:register_page, page}, _from, state) do
    case state.backend.prepare_page(state.context, page, self()) do
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

  def handle_call({:begin_capture, type, key, options}, _from, state) do
    cond do
      state.pending_capture ->
        pending = state.pending_capture

        {:reply,
         {:error, "cannot start an event expectation while #{inspect(pending.type)} #{inspect(pending.key)} is pending"},
         state}

      Map.has_key?(state.results, key) ->
        {:reply,
         {:error,
          "captured result key #{inspect(key)} is already in use; event result keys are immutable within a session"},
         state}

      true ->
        token = make_ref()
        pending = %{token: token, type: type, key: key, options: options}
        {:reply, {:ok, token}, %{state | pending_capture: pending}}
    end
  end

  def handle_call(:pending_capture, _from, state), do: {:reply, {:ok, state.pending_capture}, state}

  def handle_call({:record_capture, token, value}, _from, %{pending_capture: %{token: token} = pending} = state) do
    if Map.has_key?(pending, :captured) do
      {:reply, {:error, "event token #{inspect(token)} already has a captured value"}, state}
    else
      {:reply, :ok, %{state | pending_capture: Map.put(pending, :captured, value)}}
    end
  end

  def handle_call({:record_capture, token, _value}, _from, state), do: {:reply, stale_capture(token), state}

  def handle_call({:finish_capture, token, value}, _from, %{pending_capture: %{token: token} = pending} = state) do
    type = if pending.type == :popup, do: :page, else: pending.type
    results = Map.put(state.results, pending.key, %{type: type, value: value})
    {:reply, :ok, %{state | pending_capture: nil, results: results}}
  end

  def handle_call({:finish_capture, token, _value}, _from, state), do: {:reply, stale_capture(token), state}

  def handle_call({:cancel_capture, token}, _from, %{pending_capture: %{token: token}} = state),
    do: {:reply, :ok, %{state | pending_capture: nil}}

  def handle_call({:cancel_capture, _token}, _from, state), do: {:reply, :ok, state}

  def handle_call({:fetch_result, key, type}, _from, state) do
    result =
      case Map.fetch(state.results, key) do
        {:ok, %{type: ^type, value: value}} ->
          {:ok, value}

        {:ok, %{type: actual_type}} ->
          {:error, "captured result #{inspect(key)} contains #{inspect(actual_type)}, expected #{inspect(type)}"}

        :error ->
          {:error, "no captured result exists under #{inspect(key)}"}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    if ref in state.monitors, do: {:stop, :normal, state}, else: {:noreply, state}
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

  defp stale_capture(token), do: {:error, "event token #{inspect(token)} is no longer pending"}

  defp register_page_reply(state, registration) do
    case put_page(state, registration) do
      {:ok, id, updated} -> {:reply, {:ok, id}, updated}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  defp put_page(state, {page, external_id, opener_id}) do
    existing = if external_id, do: state.external_pages[external_id]

    cond do
      existing && not Map.has_key?(state.pages, existing) -> {:ok, existing, state}
      existing && is_nil(page.name) -> {:ok, existing, state}
      true -> store_page(state, page, external_id, opener_id, existing)
    end
  end

  defp store_page(state, page, external_id, opener_id, existing) do
    id = existing || make_ref()
    name = page.name

    if name && Map.has_key?(state.names, name) && state.names[name] != id do
      {:error, "page name #{inspect(name)} is already in use"}
    else
      opener = if opener_id, do: state.external_pages[opener_id], else: page.opener
      page = %{page | id: id, opener: if(Map.has_key?(state.pages, opener), do: opener)}
      state = %{state | pages: Map.put(state.pages, id, page)}
      state = if name, do: %{state | names: Map.put(state.names, name, id)}, else: state
      state = if external_id, do: %{state | external_pages: Map.put(state.external_pages, external_id, id)}, else: state
      {:ok, id, state}
    end
  end

  defp remove_page(state, id) do
    {page, pages} = Map.pop(state.pages, id)

    if page do
      # Like Playwright, a live page has no opener once that opener closes.
      pages = Map.new(pages, fn {key, page} -> {key, if(page.opener == id, do: %{page | opener: nil}, else: page)} end)
      names = Map.reject(state.names, fn {_name, value} -> value == id end)
      %{state | pages: pages, names: names}
    else
      state
    end
  end

  defp safely(fun) do
    fun.()
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end
end
