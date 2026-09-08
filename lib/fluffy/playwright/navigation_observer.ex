defmodule Fluffy.Playwright.NavigationObserver do
  @moduledoc false

  alias Fluffy.PlaywrightEventListener
  alias PlaywrightEx.Connection

  @enforce_keys [:listener]
  defstruct [:listener]

  @opaque t :: %__MODULE__{listener: pid()}

  def arm(context_id, page_id, frame_id, timeout) do
    {:ok, listener} =
      PlaywrightEventListener.start_link(
        guid: context_id,
        filter: &main_document_response?(&1, page_id, frame_id),
        handler: &normalize_response/1,
        subscription: :response,
        timeout: timeout
      )

    %__MODULE__{listener: listener}
  end

  def arm_popup(context_id, opener_frame_id, timeout) do
    {:ok, listener} =
      PlaywrightEventListener.start_link(
        guid: context_id,
        filter: &popup_document_response?(&1, opener_frame_id),
        handler: &normalize_response/1,
        subscription: :response,
        timeout: timeout
      )

    %__MODULE__{listener: listener}
  end

  def await(%__MODULE__{listener: listener}, timeout) do
    PlaywrightEventListener.await(listener, timeout)
  end

  def stop(%__MODULE__{listener: listener}) do
    PlaywrightEventListener.stop(listener)
  end

  defp main_document_response?(%{method: :response} = event, page_id, frame_id) do
    case response_context(event) do
      %{page_id: response_page_id, frame_id: ^frame_id, resource_type: "document"}
      when response_page_id in [nil, page_id] ->
        true

      _other ->
        false
    end
  end

  defp main_document_response?(_event, _page_id, _frame_id), do: false

  defp popup_document_response?(%{method: :response} = event, opener_frame_id) do
    case response_context(event) do
      %{frame_id: frame_id, resource_type: "document"} when frame_id != opener_frame_id -> true
      _other -> false
    end
  end

  defp popup_document_response?(_event, _opener_frame_id), do: false

  defp response_context(%{params: %{response: %{guid: response_id}} = params}) do
    response = initializer!(response_id)
    request = initializer!(response.request.guid)

    %{
      frame_id: get_in(request, [:frame, :guid]),
      page_id: get_in(params, [:page, :guid]),
      resource_type: request.resource_type,
      response: response
    }
  end

  defp response_context(_event), do: nil

  defp normalize_response(%{params: %{response: %{guid: response_id}} = params}) do
    response = initializer!(response_id)
    request = initializer!(response.request.guid)

    {:ok,
     %{
       frame_id: get_in(request, [:frame, :guid]),
       page_id: get_in(params, [:page, :guid]),
       status: response.status,
       url: response.url
     }}
  end

  defp initializer!(guid) do
    Connection.initializer!(PlaywrightEx.Supervisor.Connection, guid)
  end
end
