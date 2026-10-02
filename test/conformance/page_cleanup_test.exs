defmodule Fluffy.Conformance.PageCleanupTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
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
      |> expect_event(Event.popup(), &click(&1, by_role(:link, name: "Open child")))

    page_ids = Enum.map(Session.pages(session), fn {_id, page} -> page.state.page_id end)
    assert length(page_ids) == 2
    :ok = GenServer.stop(TestScope.current())

    for page_id <- page_ids do
      assert {:error, _reason} = BrowserPage.bring_to_front(page_id, timeout: 100)
    end
  end

  @tag driver: :playwright
  test "page actions and opener assertions reject names" do
    session = start_session(:playwright)
    main = current_page(session)

    assert_raise FunctionClauseError, fn -> apply(Fluffy, :switch_page, [session, :main]) end
    assert_raise FunctionClauseError, fn -> apply(Fluffy, :close_page, [session, :main]) end
    assert_raise FunctionClauseError, fn -> apply(Fluffy.Expect, :page_to_have_opener, [:main]) end

    assert current_page(session) == main
    assert pages(session) == [main]
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

    {:ok, resources} = Fluffy.SessionRuntime.resources(session.runtime)

    refute {:live_view, page.state.view.pid} in resources
    refute {:live_view, live_view_proxy_pid(page)} in resources
  end

  defp live_view_proxy_pid(page) do
    {_reference, _topic, proxy_pid} = page.state.view.proxy
    proxy_pid
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end
