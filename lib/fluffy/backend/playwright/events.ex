defmodule Fluffy.Backend.Playwright.Events do
  @moduledoc false

  import Fluffy.Event, only: [is_network_type: 1]

  alias Fluffy.Backend.Playwright.Listeners
  alias Fluffy.ConsoleMessage
  alias Fluffy.Dialog
  alias Fluffy.Download
  alias Fluffy.FileChooser
  alias Fluffy.Page
  alias Fluffy.PageError
  alias Fluffy.Session
  alias Fluffy.SessionRuntime
  alias Fluffy.WebSocket
  alias Fluffy.Worker
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Page, as: BrowserPage

  def event_source(session, type, scope) do
    if type == :page or (is_network_type(type) and scope == :context) do
      Session.context(session)
      :context
    else
      session |> Session.handle() |> checked_page() |> Page.id()
    end
  end

  # Native listeners only forward to the subscription process, which decodes.
  def subscribe_event(session, type, source, recipient) do
    listeners =
      case source do
        :context ->
          [{BrowserContext, Session.context(session).browser_context, type}]

        # The runtime reports a source page's close (see decode); a native close
        # listener would race that report.
        _page_id when type == :close ->
          []

        page_id ->
          page = Page.record(Page.new(session.runtime, page_id)).state.page
          Enum.uniq([{BrowserPage, page, type}, {BrowserPage, page, :crash}])
      end

    listeners =
      Listeners.register(
        for {module, target, event} <- listeners,
            do: {module, target, event, fn native -> send(recipient, {:fluffy_playwright_event, event, native}) end}
      )

    unsubscribe = fn -> Listeners.release(listeners) end

    decode = fn
      {:source_closed, _reason} when type == :close ->
        {:ok, Page.new(session.runtime, source)}

      {:fluffy_playwright_event, :crash, _page} when type != :crash ->
        {:error, "event source crashed"}

      {:fluffy_playwright_event, _event, native} when type in [:page_error, :worker, :web_socket] ->
        {:ok, source_value(session, type, source, native)}

      {:fluffy_playwright_event, _event, native} ->
        {:ok, value(session, type, native)}

      _message ->
        :ignore
    end

    {decode, unsubscribe}
  end

  defp checked_page(page) do
    Page.record(page)
    page
  end

  defp value(session, :download, download) do
    %Download{
      suggested_filename: PlaywrightEx.Download.suggested_filename(download),
      url: PlaywrightEx.Download.url(download),
      page: page_handle(session, PlaywrightEx.Download.page(download)),
      native: download
    }
  end

  defp value(session, type, browser_page) when type in [:page, :popup, :load, :dom_content_loaded, :crash],
    do: page_handle(session, browser_page)

  defp value(session, :dialog, dialog) do
    %Dialog{
      type: dialog_type(PlaywrightEx.Dialog.type(dialog)),
      message: PlaywrightEx.Dialog.message(dialog),
      default_value: PlaywrightEx.Dialog.default_value(dialog),
      page: dialog |> PlaywrightEx.Dialog.page() |> optional_page_handle(session),
      native: dialog
    }
  end

  defp value(session, :file_chooser, chooser) do
    %FileChooser{
      native: chooser,
      page: page_handle(session, PlaywrightEx.FileChooser.page(chooser)),
      multiple?: PlaywrightEx.FileChooser.is_multiple(chooser)
    }
  end

  defp value(session, type, frame) when type in [:frame_navigated, :frame_attached, :frame_detached] do
    Fluffy.Frame.new(page_handle(session, PlaywrightEx.Frame.page(frame)), frame)
  end

  defp value(session, type, request) when type in [:request, :request_failed, :request_finished],
    do: request(session, request)

  defp value(session, :response, response) do
    %Fluffy.Response{
      url: PlaywrightEx.Response.url(response),
      status: PlaywrightEx.Response.status(response),
      status_text: PlaywrightEx.Response.status_text(response),
      headers: PlaywrightEx.Response.headers(response),
      request: request(session, PlaywrightEx.Response.request(response)),
      native: response
    }
  end

  defp value(session, :console, message) do
    %ConsoleMessage{
      type: PlaywrightEx.ConsoleMessage.type(message),
      text: PlaywrightEx.ConsoleMessage.text(message),
      location: PlaywrightEx.ConsoleMessage.location(message),
      timestamp: PlaywrightEx.ConsoleMessage.timestamp(message),
      page: message |> PlaywrightEx.ConsoleMessage.page() |> optional_page_handle(session),
      native: message
    }
  end

  # These upstream values do not name their page, which is the event's source.
  defp source_value(session, :page_error, source, error) do
    %PageError{
      name: error.name,
      message: Exception.message(error),
      stack: error.stack,
      page: Page.new(session.runtime, source),
      native: error
    }
  end

  defp source_value(session, :worker, source, worker) do
    %Worker{url: PlaywrightEx.Worker.url(worker), page: Page.new(session.runtime, source), native: worker}
  end

  defp source_value(session, :web_socket, source, web_socket) do
    %WebSocket{url: PlaywrightEx.WebSocket.url(web_socket), page: Page.new(session.runtime, source), native: web_socket}
  end

  # Also builds the redirects of a `Fluffy.Request`, which has only the runtime.
  @doc false
  def request(session, request) do
    %Fluffy.Request{
      url: PlaywrightEx.Request.url(request),
      method: PlaywrightEx.Request.method(request),
      headers: PlaywrightEx.Request.headers(request),
      resource_type: PlaywrightEx.Request.resource_type(request),
      post_data: PlaywrightEx.Request.post_data_buffer(request),
      page: request_page(session, request),
      native: request,
      runtime: session.runtime
    }
  end

  # A request's page is optional, so a page that closed unseen leaves it nil.
  defp request_page(session, request) do
    frame = request_frame(request)

    case frame && live_page_handle(session, PlaywrightEx.Frame.page(frame)) do
      {:ok, page} -> page
      _none -> nil
    end
  end

  # Service worker requests, and a navigation request issued before its frame
  # is attached (a popup's first request), have no frame. `Request.frame/1`
  # reads cached state and raises a plain `RuntimeError` only for a request
  # without one; a closed connection still raises `TargetClosedError`.
  def request_frame(request) do
    if is_nil(PlaywrightEx.Request.service_worker(request)), do: PlaywrightEx.Request.frame(request)
  rescue
    RuntimeError -> nil
  end

  defp optional_page_handle(nil, _session), do: nil
  defp optional_page_handle(browser_page, session), do: page_handle(session, browser_page)

  defp dialog_type("alert"), do: :alert
  defp dialog_type("confirm"), do: :confirm
  defp dialog_type("prompt"), do: :prompt
  defp dialog_type("beforeunload"), do: :beforeunload

  # Like Playwright, an event of a page that closed before Fluffy saw it, such
  # as a popup closed at once, delivers that page, closed.
  defp page_handle(session, browser_page) do
    case live_page_handle(session, browser_page) do
      {:ok, page} -> page
      :closed -> session.runtime |> SessionRuntime.closed_page(browser_page.guid) |> handle!(session)
    end
  end

  defp live_page_handle(session, browser_page) do
    case session.runtime |> SessionRuntime.external_page(browser_page.guid) |> handle!(session) do
      nil -> register_page(session, browser_page)
      page -> {:ok, page}
    end
  end

  defp register_page(session, browser_page) do
    case SessionRuntime.register_page(session.runtime, Fluffy.Backend.Playwright.page_record(browser_page)) do
      {:ok, id} -> {:ok, Page.new(session.runtime, id)}
      {:error, _closed} -> :closed
    end
  end

  defp handle!({:ok, nil}, _session), do: nil
  defp handle!({:ok, id}, session), do: Page.new(session.runtime, id)
  defp handle!({:error, message}, _session), do: raise(ArgumentError, message)
end
