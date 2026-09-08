defmodule Fluffy.Conformance.PageCleanupTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Backend
  alias Fluffy.Event
  alias Fluffy.Session
  alias Fluffy.TestHTTPFixtures
  alias Fluffy.TestScope
  alias PlaywrightEx.Page, as: BrowserPage

  @tag driver: :playwright
  test "closing the test scope closes every page left in its BrowserContext" do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{body: html(~s(<a href="child" target="_blank">Open child</a>))}

          "/child" ->
            %{body: html("<h1>Child</h1>")}
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.popup(:child), &click(&1, by_role(:link, name: "Open child")))

    page_ids = Enum.map(session.pages, fn {_name, page} -> page.state.page_id end)
    assert length(page_ids) == 2
    :ok = GenServer.stop(TestScope.current())

    for page_id <- page_ids do
      assert {:error, _reason} = BrowserPage.bring_to_front(page_id, timeout: 100)
    end
  end

  @tag driver: :playwright
  test "missing and duplicate page names fail before page actions" do
    session =
      Fluffy.session_for_html(:playwright, "<button>Unused</button>", base_url: Fluffy.TestServer.base_url())

    assert_raise ArgumentError, ~r/no page named :missing/, fn ->
      switch_page(session, :missing)
    end

    Process.put(:duplicate_page_action_ran, false)

    assert_raise ArgumentError, ~r/page name :main is already in use/, fn ->
      wait_for(session, Event.popup(:main), fn session ->
        Process.put(:duplicate_page_action_ran, true)
        session
      end)
    end

    refute Process.get(:duplicate_page_action_ran)
    assert Session.current_page(session).id == :main
  end

  @tag driver: :phoenix
  test "replacing a Live document with Static releases its page resources" do
    session = :phoenix |> start_session() |> visit("/live/chamber-map")
    live_page = Session.current_page(session)

    assert_live_page_alive(live_page)

    session = click(session, by_role(:link, name: "Sleeping chamber"))

    assert Session.current_driver(session) == :static
    assert_live_page_released(session, live_page)
  end

  @tag driver: :phoenix
  test "replacing a Live document with another Live document releases the old resources" do
    session = :phoenix |> start_session() |> visit("/live/chamber-map")
    old_page = Session.current_page(session)

    session = click(session, by_role(:link, name: "Secret chamber"))

    assert Session.current_driver(session) == :live
    assert_live_page_alive(Session.current_page(session))
    assert_live_page_released(session, old_page)
  end

  @tag driver: :phoenix
  test "session cleanup releases Live resources and remains idempotent" do
    session = :phoenix |> start_session() |> visit("/live/chamber-map")
    page = Session.current_page(session)

    assert :ok = Backend.close_session(session)
    assert :ok = Backend.close_session(session)
    refute Process.alive?(page.state.view.pid)
    refute Process.alive?(live_view_proxy_pid(page))
    refute Process.alive?(page.state.watcher)
  end

  defp assert_live_page_alive(page) do
    assert Process.alive?(page.state.view.pid)
    assert Process.alive?(live_view_proxy_pid(page))
    assert Process.alive?(page.state.watcher)
  end

  defp assert_live_page_released(session, page) do
    refute Process.alive?(page.state.view.pid)
    refute Process.alive?(live_view_proxy_pid(page))
    refute Process.alive?(page.state.watcher)

    resources =
      TestScope.current()
      |> TestScope.status()
      |> get_in([:sessions, session.context.resource_id])
      |> Kernel.||([])

    refute {:live_view, page.state.view.pid} in resources
    refute {:live_view, live_view_proxy_pid(page)} in resources
  end

  defp live_view_proxy_pid(page) do
    {_reference, _topic, proxy_pid} = page.state.view.proxy
    proxy_pid
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end
