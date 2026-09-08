defmodule Fluffy.PlaywrightSessionTest do
  use Fluffy.TestCase, async: false

  alias Fluffy.Backend.Playwright, as: PlaywrightBackend
  alias Fluffy.Driver.Playwright, as: PlaywrightDriver
  alias Fluffy.Driver.Registry, as: DriverRegistry
  alias Fluffy.Session
  alias PlaywrightEx.Frame

  test "loads the harness page and its built JavaScript asset" do
    session = Fluffy.start_session(:playwright)

    session = Fluffy.visit(session, "/stage")

    assert session.backend == PlaywrightBackend
    assert Session.current_driver(session) == :playwright
    assert DriverRegistry.module(Session.current_driver(session)) == PlaywrightDriver
    state = Session.page_state(session)

    assert {:ok, "ready"} =
             Frame.evaluate(state.frame_id,
               expression: "document.documentElement.dataset.fluffyTestBrowser",
               timeout: 5_000
             )
  end

  test "a LiveView visit and reload wait for the browser connection" do
    session = Fluffy.start_session(:playwright, base_url: Fluffy.TestServer.base_url())

    session = Fluffy.visit(session, "/live/three-heads")
    assert_live_view_connected(session)

    session = Fluffy.reload(session)
    assert_live_view_connected(session)
  end

  defp assert_live_view_connected(session) do
    state = Session.page_state(session)

    assert {:ok, true} =
             Frame.evaluate(state.frame_id,
               expression: "document.querySelector('[data-phx-main]').classList.contains('phx-connected')",
               timeout: 5_000
             )
  end
end
