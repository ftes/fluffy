defmodule Fluffy.Backend.Playwright.Events do
  @moduledoc false

  import Fluffy.Event, only: [is_network_type: 1]

  alias Fluffy.Backend.Playwright.Listeners
  alias Fluffy.Download
  alias Fluffy.FileChooser
  alias Fluffy.Page
  alias Fluffy.Session
  alias Fluffy.SessionRuntime
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

  defp value(session, :file_chooser, chooser) do
    %FileChooser{
      native: chooser,
      page: page_handle(session, PlaywrightEx.FileChooser.page(chooser)),
      multiple?: PlaywrightEx.FileChooser.is_multiple(chooser)
    }
  end

  # As in Playwright, other events deliver PlaywrightEx's values.
  defp value(_session, _type, native), do: native

  @doc false
  def page(session, browser_page) do
    if BrowserPage.context(browser_page).guid != Session.context(session).browser_context.guid,
      do: raise(ArgumentError, "the page belongs to another browser context than the session's")

    page_handle(session, browser_page)
  end

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
