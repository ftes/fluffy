defmodule Fluffy.Backend.Playwright.Events do
  @moduledoc false

  alias Fluffy.Dialog
  alias Fluffy.Download
  alias Fluffy.FileChooser
  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.SessionRuntime
  alias PlaywrightEx.BrowserContext
  alias PlaywrightEx.Page, as: BrowserPage

  # What `PlaywrightEx.Request.frame/1` raises for a request without a frame.
  @no_frame [
    "Service Worker requests do not have an associated frame",
    "Frame for this navigation request is not available"
  ]

  def event_source(session, type, scope) do
    if type == :page or (type in [:request, :response] and scope == :context) do
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
          [{BrowserPage, page, type}, {BrowserPage, page, :crash}]
      end

    # A failed registration releases the listeners registered before it.
    listeners =
      Enum.reduce(listeners, [], fn {module, target, event}, registered ->
        listener = fn native -> send(recipient, {:fluffy_playwright_event, event, native}) end

        try do
          module.on(target, event, listener)
        catch
          kind, reason ->
            unsubscribe(registered)
            :erlang.raise(kind, reason, __STACKTRACE__)
        end

        [{module, target, event, listener} | registered]
      end)

    unsubscribe = fn -> unsubscribe(listeners) end

    decode = fn
      {:source_closed, _reason} when type == :close -> {:ok, Page.new(session.runtime, source)}
      {:fluffy_playwright_event, :crash, _page} -> {:error, "event source crashed"}
      {:fluffy_playwright_event, _event, native} -> {:ok, value(session, type, native)}
      _message -> :ignore
    end

    {decode, unsubscribe}
  end

  defp unsubscribe(listeners) do
    for {module, target, event, listener} <- listeners do
      try do
        module.off(target, event, listener)
      catch
        # A lost driver already released its listeners. Cleanup must
        # preserve the event outcome or the caller's original callback failure.
        _kind, _reason -> :ok
      end
    end

    :ok
  end

  defp checked_page(page) do
    Page.record(page)
    page
  end

  defp value(session, :download, download) do
    %Download{
      suggested_filename: PlaywrightEx.Download.suggested_filename(download),
      url: PlaywrightEx.Download.url(download),
      runtime: session.runtime,
      source: download
    }
  end

  defp value(session, type, browser_page) when type in [:page, :popup], do: page_handle(session, browser_page)

  defp value(_session, :dialog, dialog) do
    %Dialog{
      type: dialog_type(PlaywrightEx.Dialog.type(dialog)),
      message: PlaywrightEx.Dialog.message(dialog),
      default_value: PlaywrightEx.Dialog.default_value(dialog),
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

  defp value(session, :frame_navigated, frame) do
    Fluffy.Frame.new(page_handle(session, PlaywrightEx.Frame.page(frame)), frame)
  end

  defp value(session, :request, request), do: request(session, request)

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

  defp request(session, request) do
    %Fluffy.Request{
      url: PlaywrightEx.Request.url(request),
      method: PlaywrightEx.Request.method(request),
      headers: PlaywrightEx.Request.headers(request),
      resource_type: PlaywrightEx.Request.resource_type(request),
      post_data: PlaywrightEx.Request.post_data(request),
      page: request_page(session, request),
      native: request
    }
  end

  # Service worker requests, and a popup's first request, have no frame yet.
  # `Request.frame/1` raises for both; other errors surface.
  defp request_page(session, request) do
    page_handle(session, request |> PlaywrightEx.Request.frame() |> PlaywrightEx.Frame.page())
  rescue
    error in RuntimeError ->
      if String.starts_with?(error.message, @no_frame), do: nil, else: reraise(error, __STACKTRACE__)
  end

  defp dialog_type("alert"), do: :alert
  defp dialog_type("confirm"), do: :confirm
  defp dialog_type("prompt"), do: :prompt
  defp dialog_type("beforeunload"), do: :beforeunload

  def page_handle(session, browser_page) do
    case SessionRuntime.external_page(session.runtime, browser_page.guid) do
      {:ok, nil} -> register_page(session, browser_page)
      {:ok, id} -> Page.new(session.runtime, id)
      {:error, message} -> raise ArgumentError, message
    end
  end

  defp register_page(session, browser_page) do
    case SessionRuntime.register_page(session.runtime, Fluffy.Backend.Playwright.page_record(browser_page)) do
      {:ok, id} -> Page.new(session.runtime, id)
      {:error, message} -> raise ArgumentError, message
    end
  end
end
