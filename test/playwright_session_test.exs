defmodule Fluffy.PlaywrightSessionTest do
  use Fluffy.TestCase, async: false

  alias Fluffy.Backend.Playwright, as: PlaywrightBackend
  alias Fluffy.Backend.Playwright.Document
  alias Fluffy.Driver.Playwright, as: PlaywrightDriver
  alias Fluffy.Driver.Registry, as: DriverRegistry
  alias Fluffy.Session
  alias PlaywrightEx.Frame
  alias PlaywrightEx.Runtime.Heap

  test "loads the harness page and its built JavaScript asset" do
    session = Fluffy.start_session(:playwright)

    session = Fluffy.visit(session, "/stage")

    assert Session.backend(session) == PlaywrightBackend
    assert Session.current_driver(session) == :playwright
    assert DriverRegistry.module(Session.current_driver(session)) == PlaywrightDriver
    state = Session.page_state(session)

    assert {:ok, "ready"} = Frame.evaluate(state.frame, "document.documentElement.dataset.fluffyTestBrowser")
  end

  test "a LiveView visit and reload wait for the browser connection" do
    session = Fluffy.start_session(:playwright, base_url: Fluffy.TestServer.base_url())

    session = Fluffy.visit(session, "/live/three-heads")
    assert_live_view_connected(session)

    session = Fluffy.reload(session)
    assert_live_view_connected(session)
  end

  test "a session starts when the Playwright config leaves out timeout:" do
    config = Application.fetch_env!(:fluffy, :playwright)
    Application.put_env(:fluffy, :playwright, Keyword.delete(config, :timeout))
    on_exit(fn -> Application.put_env(:fluffy, :playwright, config) end)

    assert Session.context(Fluffy.start_session(:playwright)).timeout == 15_000
    assert Session.context(Fluffy.start_session(:playwright, timeout: 2_000)).timeout == 2_000
  end

  test "subscribing an already closed page reports it and leaves no close listener" do
    session = Fluffy.start_session(:playwright)
    browser_page = PlaywrightEx.BrowserContext.new_page!(Session.context(session).browser_context)
    :ok = PlaywrightEx.Page.close!(browser_page)
    listeners = fn -> PlaywrightEx.Client.EventEmitter.listener_count(browser_page, "close") end
    before = listeners.()

    assert {:error, "page nil is closed"} =
             PlaywrightBackend.subscribe_page(nil, PlaywrightBackend.page_record(browser_page), self())

    assert listeners.() == before
  end

  test "a failed adopted document read keeps the page flagged as navigated" do
    session = Fluffy.start_session(:playwright)
    browser_page = PlaywrightEx.BrowserContext.new_page!(Session.context(session).browser_context)
    state = PlaywrightBackend.page_record(browser_page).state
    :ok = PlaywrightEx.Page.close!(browser_page)

    assert_raise PlaywrightEx.TargetClosedError, fn -> Document.adopted_probe!(state, nil, 1_000) end
    assert Document.navigated?(state)
  end

  # Document probes retry on this message; guard it against driver rewording.
  test "a navigation during an evaluate reports the destroyed context Fluffy retries on" do
    session = :playwright |> Fluffy.start_session() |> Fluffy.visit("/stage")
    frame = Session.page_state(session).frame
    script = "() => { location.href = '/stage?replaced'; return new Promise(() => {}) }"

    assert {:error, error} = Frame.evaluate(frame, script)
    assert Document.context_destroyed?(error), Exception.message(error)
  end

  test "LiveView waits leave no handles behind" do
    session =
      :playwright
      |> Fluffy.start_session(base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
      |> Fluffy.visit("/live/chamber-map")
      |> Fluffy.click(Fluffy.Locator.by_role(:link, name: "Reveal passage"))
      |> Fluffy.fill(Fluffy.Locator.by_label("Map step"), "patched")

    frame = Session.page_state(session).frame
    assert eventually(fn -> frame_handles(frame) == [] end)
  end

  # The handles PlaywrightEx tracks whose results live in the frame.
  defp frame_handles(frame) do
    connection = Heap.get(frame, :_connection)

    for object <- Heap.map_values(connection, :_objects),
        Heap.get(object, :_type) == "JSHandle",
        Heap.get(object, :_parent).guid == frame.guid,
        do: object.guid
  end

  # Handles are disposed without awaiting the reply.
  defp eventually(fun, attempts \\ 50) do
    cond do
      fun.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(fun, attempts - 1)
    end
  end

  defp assert_live_view_connected(session) do
    state = Session.page_state(session)

    assert {:ok, true} =
             Frame.evaluate(state.frame, "document.querySelector('[data-phx-main]').classList.contains('phx-connected')")
  end
end
