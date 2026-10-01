defmodule Fluffy.Backend.Playwright.Events do
  @moduledoc false

  alias Fluffy.Dialog
  alias Fluffy.Download
  alias Fluffy.FileChooser
  alias Fluffy.HTTPEvent
  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.SessionRuntime
  alias PlaywrightEx.Connection
  alias PlaywrightEx.Download, as: BrowserDownload

  def event_source(session, type, scope) do
    if type == :page or (type in [:request, :response] and scope == :context) do
      Session.context(session)
      :context
    else
      session |> Session.handle() |> checked_page() |> Page.id()
    end
  end

  def subscribe_event(session, type, source, recipient) do
    context = Session.context(session)
    page_id = if source != :context, do: Page.record(Page.new(session.runtime, source)).state.page_id
    subscriptions = subscriptions(context.context_id, page_id, type)
    Code.ensure_loaded!(BrowserDownload)
    Code.ensure_loaded!(Fluffy.Frame)

    unsubscribe = fn ->
      try do
        for {guid, _event} <- subscriptions do
          Connection.unsubscribe_sync(context.connection, recipient, guid)
        end

        :ok
      catch
        # A lost connection already released its subscriptions. Cleanup must
        # preserve the event outcome or the caller's original callback failure.
        :exit, _reason -> :ok
      end
    end

    try do
      for {guid, event} <- subscriptions do
        case Connection.subscribe_event(context.connection, recipient, guid, event) do
          :ok -> :ok
          {:error, reason} -> raise ArgumentError, "event source is closed: #{inspect(reason)}"
        end
      end

      decode = fn
        {:playwright_msg, %{guid: guid, method: method}} when method in [:close, :crash, :__dispose__] ->
          if guid in Enum.map(subscriptions, &elem(&1, 0)),
            do: {:error, "event source #{if method == :crash, do: "crashed", else: "is closed"}"},
            else: :ignore

        {:playwright_msg, message} ->
          decode(session, context, page_id, type, message)

        _message ->
          :ignore
      end

      {decode, unsubscribe}
    catch
      kind, reason ->
        unsubscribe.()
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp checked_page(page) do
    Page.record(page)
    page
  end

  defp subscriptions(context_id, _page_id, :page), do: [{context_id, :page}]
  defp subscriptions(context_id, page_id, :popup), do: [{context_id, :page}, {page_id, :close}]
  defp subscriptions(context_id, nil, type) when type in [:request, :response], do: [{context_id, type}]

  defp subscriptions(context_id, page_id, type) when type in [:request, :response],
    do: [{context_id, type}, {page_id, :close}]

  defp subscriptions(_context_id, page_id, type), do: [{page_id, type}]

  defp decode(session, context, _page_id, :download, %{method: :download} = message) do
    source = BrowserDownload.from_event(message, connection: context.connection)

    {:ok,
     %Download{
       suggested_filename: source.suggested_filename,
       url: source.url,
       runtime: session.runtime,
       source: source,
       timeout: context.timeout
     }}
  end

  defp decode(session, context, opener_id, type, %{method: :page, params: %{page: %{guid: guid}}})
       when type in [:page, :popup] do
    initializer = Connection.initializer!(context.connection, guid)

    if type == :page or initializer[:opener] == %{guid: opener_id},
      do: {:ok, page_handle(session, context, guid)},
      else: :ignore
  end

  defp decode(_session, context, _page_id, :dialog, %{method: :__create__, params: %{type: "Dialog"} = params}) do
    initializer = params.initializer

    type =
      case initializer.type do
        "alert" -> :alert
        "confirm" -> :confirm
        "prompt" -> :prompt
        "beforeunload" -> :beforeunload
      end

    {:ok,
     %Dialog{
       type: type,
       message: initializer.message,
       default_value: initializer[:default_value] || "",
       connection: context.connection,
       id: params.guid,
       timeout: context.timeout
     }}
  end

  defp decode(session, context, page_id, :file_chooser, %{method: :file_chooser, params: params}) do
    {:ok,
     %FileChooser{
       element_id: params.element.guid,
       page: page_handle(session, context, page_id),
       multiple?: params.is_multiple
     }}
  end

  defp decode(session, context, page_id, :frame_navigated, %{method: :frame_navigated, params: params}) do
    {:ok, Fluffy.Frame.new(page_handle(session, context, page_id), params.frame.guid)}
  end

  defp decode(session, context, page_id, type, %{method: type, params: params}) when type in [:request, :response] do
    if is_nil(page_id) or params[:page] == %{guid: page_id} do
      {:ok, http_event(session, context, type, params)}
    else
      :ignore
    end
  end

  defp decode(_session, _context, _page_id, _type, _message), do: :ignore

  defp http_event(session, context, type, params) do
    response = if type == :response, do: Connection.initializer!(context.connection, params.response.guid)
    request_guid = if response, do: response.request.guid, else: params.request.guid
    request = Connection.initializer!(context.connection, request_guid)
    metadata = response || request

    %HTTPEvent{
      kind: type,
      method: request.method,
      url: metadata.url,
      headers: Map.new(metadata.headers, fn %{name: name, value: value} -> {String.downcase(name), value} end),
      resource_type: request.resource_type,
      post_data: decode_binary(request[:post_data]),
      status: metadata[:status],
      status_text: metadata[:status_text],
      page: if(params[:page], do: page_handle(session, context, params.page.guid))
    }
  end

  defp decode_binary(nil), do: nil
  defp decode_binary(value), do: Base.decode64!(value)

  defp page_handle(session, context, guid) do
    case SessionRuntime.external_page(session.runtime, guid) do
      {:ok, nil} -> register_page(session, context, guid)
      {:ok, id} -> Page.new(session.runtime, id)
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp register_page(session, context, guid) do
    page = Fluffy.Backend.Playwright.page_record(context, guid)

    case SessionRuntime.register_page(session.runtime, page) do
      {:ok, id} -> Page.new(session.runtime, id)
      {:error, message} -> raise ArgumentError, message
    end
  end
end
