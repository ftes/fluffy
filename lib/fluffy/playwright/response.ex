defmodule Fluffy.Playwright.Response do
  @moduledoc false

  alias PlaywrightEx.Connection
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Request

  def for_document(frame_id, options) do
    with {:ok, request} <- Frame.document_request(frame_id, Keyword.take(options, [:connection])) do
      for_request(request, options)
    end
  end

  def for_request(nil, _options), do: {:ok, nil}

  def for_request(%{guid: request_id}, options) do
    with {:ok, response} <- Request.response(request_id, options) do
      connection = Keyword.fetch!(options, :connection)
      {:ok, if(response, do: Connection.initializer!(connection, response.guid))}
    end
  end
end
