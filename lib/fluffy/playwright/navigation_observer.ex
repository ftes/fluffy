defmodule Fluffy.Playwright.NavigationObserver do
  @moduledoc false

  use GenServer

  alias Fluffy.Playwright.SubscriptionRegistry
  alias Fluffy.PlaywrightEventListener
  alias PlaywrightEx.Connection
  alias PlaywrightEx.EventWaiter

  @enforce_keys [:listener, :connection, :context_id, :frame_id]
  defstruct @enforce_keys

  @opaque t :: %__MODULE__{listener: pid(), connection: atom(), context_id: String.t(), frame_id: String.t() | nil}

  def arm(context_id, page_id, frame_id, timeout, connection \\ PlaywrightEx.Supervisor.Connection) do
    start(context_id, page_id, frame_id, timeout, connection)
  end

  def arm_popup(context_id, timeout, connection) do
    start(context_id, nil, nil, timeout, connection)
  end

  defp start(context_id, page_id, frame_id, timeout, connection) do
    {:ok, listener} =
      GenServer.start_link(__MODULE__, %{
        connection: connection,
        context_id: context_id,
        page_id: page_id,
        frame_id: frame_id,
        timeout: timeout,
        owner: self()
      })

    %__MODULE__{listener: listener, connection: connection, context_id: context_id, frame_id: frame_id}
  end

  def await(observer, timeout, selection \\ []) do
    request_id = Keyword.get_lazy(selection, :request_id, fn -> GenServer.call(observer.listener, :request_id) end)
    selection = selection |> Keyword.put(:request_id, request_id) |> Keyword.put_new(:frame_id, observer.frame_id)
    predicate = &matches?(normalize_response(&1, observer.connection), selection)

    with {:ok, waiter} <-
           EventWaiter.arm(observer.context_id, :response,
             connection: observer.connection,
             timeout: timeout,
             predicate: predicate
           ) do
      try do
        # Subscribe before reading the cache so a response cannot fall between them.
        case GenServer.call(observer.listener, {:response, selection}) do
          nil ->
            with {:ok, event} <- EventWaiter.await(waiter), do: {:ok, normalize_response(event, observer.connection)}

          response ->
            {:ok, response}
        end
      after
        EventWaiter.cancel(waiter)
      end
    end
  end

  def stop(%__MODULE__{listener: listener}), do: PlaywrightEventListener.stop(listener)

  @impl true
  def init(state) do
    reference = Process.monitor(state.owner)
    SubscriptionRegistry.acquire(state.context_id, :response, max(state.timeout, 1), state.connection)
    :ok = Connection.subscribe_sync(state.connection, self(), state.context_id)
    if state.frame_id, do: Connection.subscribe_sync(state.connection, self(), state.frame_id)
    {:ok, Map.merge(state, %{owner_reference: reference, request_id: nil, responses: []})}
  end

  @impl true
  def handle_call(:request_id, _from, state), do: {:reply, state.request_id, state}

  def handle_call({:response, selection}, _from, state) do
    {:reply, Enum.find(state.responses, &matches?(&1, selection)), state}
  end

  @impl true
  def handle_info({:playwright_msg, %{method: :response} = event}, state) do
    response = normalize_response(event, state.connection)

    if document_response?(response, state) do
      {:noreply, %{state | responses: [response | state.responses]}}
    else
      {:noreply, state}
    end
  end

  def handle_info(
        {:playwright_msg, %{method: :navigated, params: %{new_document: %{request: %{guid: request_id}}}}},
        state
      ) do
    {:noreply, %{state | request_id: request_id}}
  end

  def handle_info({:DOWN, reference, :process, _owner, _reason}, %{owner_reference: reference} = state) do
    {:stop, :normal, state}
  end

  def handle_info({:playwright_msg, _event}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    Connection.unsubscribe(state.connection, self(), state.context_id)
    if state.frame_id, do: Connection.unsubscribe(state.connection, self(), state.frame_id)
    SubscriptionRegistry.release(state.context_id, :response, max(state.timeout, 1), state.connection)
  end

  defp document_response?(response, state) do
    response.resource_type == "document" and
      (is_nil(state.frame_id) or response.frame_id == state.frame_id) and
      (is_nil(state.page_id) or response.page_id in [nil, state.page_id])
  end

  defp matches?(response, selection) do
    response.resource_type == "document" and not response.redirect? and
      Enum.all?(selection, fn
        {_key, nil} -> true
        {key, expected} -> Map.fetch!(response, key) == expected
      end)
  end

  defp normalize_response(%{params: %{response: %{guid: response_id}} = params}, connection) do
    response = Connection.initializer!(connection, response_id)
    request = Connection.initializer!(connection, response.request.guid)

    %{
      frame_id: get_in(request, [:frame, :guid]),
      page_id: get_in(params, [:page, :guid]),
      request_id: response.request.guid,
      resource_type: request.resource_type,
      status: response.status,
      redirect?:
        response.status in [301, 302, 303, 307, 308] and
          Enum.any?(response.headers, &(String.downcase(&1.name) == "location")),
      url: response.url
    }
  end
end
