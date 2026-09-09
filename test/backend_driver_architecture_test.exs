defmodule Fluffy.BackendDriverArchitectureTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Backend
  alias Fluffy.Backend.Phoenix
  alias Fluffy.Driver.Live
  alias Fluffy.Driver.Registry, as: DriverRegistry
  alias Fluffy.Driver.Static
  alias Fluffy.Internal.Navigation
  alias Fluffy.Session

  test "a durable session selects a backend separately from its active page driver" do
    session = session_for_html(:static, "<main>Static</main>")

    assert session.backend == Phoenix
    assert DriverRegistry.module(Session.current_driver(session)) == Static
  end

  test "a Static driver reports link navigation and the Phoenix backend commits it" do
    session = visit(phoenix_session(), "/actions/click")
    revision = Session.current_page(session).revision

    assert {:navigate, pending_session, %Navigation.Link{destination: "/chamber"} = intent} =
             Static.click(session, by_role(:link, name: "Enter the chamber"), [])

    assert Session.current_page(pending_session).revision == revision

    navigated_session = Backend.navigate(pending_session, intent)

    assert Session.current_driver(navigated_session) == :static
    assert Session.current_page(navigated_session).revision == revision + 1
    expect(navigated_session, "The guardian sleeps" |> by_text() |> to_be_visible())
  end

  test "a Live driver reports patches and the Phoenix backend commits them" do
    session = visit(phoenix_session(), "/live/chamber-map")
    revision = Session.current_page(session).revision

    assert {:navigate, pending_session, %Navigation.Patch{destination: "/live/chamber-map?step=patched"} = intent} =
             Live.click(session, by_role(:link, name: "Reveal passage", exact: true), [])

    assert Session.current_page(pending_session).revision == revision

    navigated_session = Backend.navigate(pending_session, intent)

    assert Session.current_driver(navigated_session) == :live
    assert Session.current_page(navigated_session).revision == revision + 1
    expect(navigated_session, Fluffy.Expect.page_to_have_url("/live/chamber-map?step=patched"))
    expect(navigated_session, "Map position: patched" |> by_text() |> to_be_visible())
  end

  test "a Static driver reports a returned native conn for backend reconciliation" do
    session = visit(phoenix_session(), "/chamber")

    assert {:navigate, ^session, %Navigation.StaticConn{conn: %Plug.Conn{}} = intent} =
             Static.unwrap(session, fn conn -> %{conn | resp_body: "<p>Native body</p>"} end)

    session = Backend.navigate(session, intent)

    assert Session.current_driver(session) == :static
    expect(session, "Native body" |> by_text() |> to_be_visible())
  end

  defp phoenix_session do
    start_session(:phoenix,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
