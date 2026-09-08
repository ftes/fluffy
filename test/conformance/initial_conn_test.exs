defmodule Fluffy.Conformance.InitialConnTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Phoenix.ConnTest

  alias Fluffy.Page
  alias Fluffy.Session

  test "uses an initial connection's authorization assign for a first Static visit only" do
    session = initial_session()

    session = visit(session, "/initial-connection/chamber")

    assert Session.current_driver(session) == :static
    expect(session, visible(by_text("Static initial principal: chamber-keeper")))

    session = visit(session, "/initial-connection/chamber")

    expect(session, Page.to_have_status(403))
    expect(session, visible(by_text("Initial authorization required")))
  end

  test "uses an initial connection's authorization assign for a first Live visit" do
    session = initial_session()

    session = visit(session, "/live/initial-connection")

    assert Session.current_driver(session) == :live
    expect(session, visible(by_text("Live initial authorization accepted")))
  end

  test "uses connect params prepared on the initial connection for the first Live mount" do
    conn =
      build_conn()
      |> Plug.Conn.assign(:initial_principal, "chamber-keeper")
      |> Phoenix.LiveViewTest.put_connect_params(%{"timezone" => "Europe/Berlin"})

    session =
      [conn: conn]
      |> phoenix_session()
      |> visit("/live/initial-connection")

    expect(session, visible(by_text("Live timezone: Europe/Berlin")))
  end

  test "an ordinary Phoenix session receives the application's authorization denial" do
    session = phoenix_session()

    session = visit(session, "/initial-connection/chamber")

    assert Session.current_driver(session) == :static
    expect(session, Page.to_have_status(403))
    expect(session, visible(by_text("Initial authorization required")))
  end

  test "consumes the initial connection before following redirect response cookies" do
    session = visit(initial_session(), "/initial-connection/redirect")

    expect(session, visible(by_text("Redirected cookie principal: chamber-keeper")))
  end

  test "rejects invalid initial connections and the Playwright backend precisely" do
    assert_raise NimbleOptions.ValidationError, ~r/:conn.*Plug\.Conn/, fn ->
      phoenix_session(conn: :not_a_conn)
    end

    assert_raise ArgumentError, ~r/:conn.*fresh, unsent.*:unset/, fn ->
      phoenix_session(conn: Plug.Conn.send_resp(build_conn(), 200, "already sent"))
    end

    assert_raise ArgumentError, ~r/:conn.*only for Phoenix/, fn ->
      start_session(:playwright,
        base_url: Fluffy.TestServer.base_url(),
        conn: build_conn()
      )
    end
  end

  defp initial_session do
    phoenix_session(conn: Plug.Conn.assign(build_conn(), :initial_principal, "chamber-keeper"))
  end

  defp phoenix_session(options \\ []) do
    start_session(
      :phoenix,
      [
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Fluffy.TestWeb.Endpoint
      ] ++ options
    )
  end
end
