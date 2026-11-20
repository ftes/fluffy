defmodule Fluffy.Conformance.InitialConnTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Phoenix.ConnTest

  alias Fluffy.Session
  alias Fluffy.Support.HTTPFixtures

  @hagrid "Basic " <> Base.encode64("hagrid:fluffy")
  @dumbledore "Basic " <> Base.encode64("dumbledore:sherbet-lemon")

  test "uses an initial connection's authorization assign for a first Static visit only" do
    session = initial_session()

    visit(session, "/initial-connection/chamber")

    assert Session.current_driver(session) == :static
    expect(session, "Static initial principal: chamber-keeper" |> by_text() |> to_be_visible())

    visit(session, "/initial-connection/chamber")

    expect(session, "Initial authorization required" |> by_text() |> to_be_visible())
  end

  test "uses an initial connection's authorization assign for a first Live visit" do
    session = initial_session()

    session = visit(session, "/live/initial-connection")

    assert Session.current_driver(session) == :live
    expect(session, "Live initial authorization accepted" |> by_text() |> to_be_visible())
  end

  test "uses connect params prepared on the initial connection for the first Live mount" do
    conn =
      build_conn()
      |> Plug.Conn.assign(:initial_principal, "chamber-keeper")
      |> Phoenix.LiveViewTest.put_connect_params(%{"timezone" => "Europe/Berlin"})

    session =
      :phoenix
      |> start_session(conn: conn)
      |> visit("/live/initial-connection")

    expect(session, "Live timezone: Europe/Berlin" |> by_text() |> to_be_visible())
  end

  test "an ordinary Phoenix session receives the application's authorization denial" do
    session = start_session(:phoenix)

    visit(session, "/initial-connection/chamber")

    assert Session.current_driver(session) == :static
    expect(session, "Initial authorization required" |> by_text() |> to_be_visible())
  end

  test "consumes the initial connection before following redirect response cookies" do
    session = visit(initial_session(), "/initial-connection/redirect")

    expect(session, "Redirected cookie principal: chamber-keeper" |> by_text() |> to_be_visible())
  end

  # As `Phoenix.ConnTest.recycle/2` keeps them, its Accept and Authorization go with every request.
  test "sends an initial connection's authorization header on every request" do
    session = start_session(:phoenix, conn: Plug.Conn.put_req_header(build_conn(), "authorization", @hagrid))

    session
    |> visit("/live/trapdoor")
    |> click(by_role(:link, name: "Climb down"))
    |> expect("Devil's Snare below the trapdoor" |> by_text() |> to_be_visible())

    assert Session.current_driver(session) == :live

    session |> visit("/live/trapdoor") |> expect("Fluffy guards the trapdoor" |> by_text() |> to_be_visible())
  end

  @tag Playwright.Test.use(extra_http_headers: %{"accept" => "text/html"})
  test "an initial connection's headers give way to the test's and the session's" do
    conn =
      build_conn()
      |> Plug.Conn.put_req_header("accept", "text/plain")
      |> Plug.Conn.put_req_header("authorization", @hagrid)

    fixture = HTTPFixtures.register(fn _request -> %{body: "<p>Owlery</p>"} end)

    for options <- [[], [extra_http_headers: %{"authorization" => @dumbledore}]] do
      :phoenix
      |> start_session([conn: conn] ++ options)
      |> visit(HTTPFixtures.path(fixture, "/first"))
      |> visit(HTTPFixtures.path(fixture, "/second"))
    end

    headers =
      for request <- HTTPFixtures.requests(fixture), do: Map.take(Map.new(request.headers), ["accept", "authorization"])

    assert headers == [
             %{"accept" => "text/html", "authorization" => @hagrid},
             %{"accept" => "text/html", "authorization" => @hagrid},
             %{"accept" => "text/plain", "authorization" => @dumbledore},
             %{"accept" => "text/plain", "authorization" => @dumbledore}
           ]
  end

  test "rejects invalid initial connections and the Playwright backend precisely" do
    assert_raise NimbleOptions.ValidationError, ~r/:conn.*Plug\.Conn/, fn ->
      start_session(:phoenix, conn: :not_a_conn)
    end

    assert_raise ArgumentError, ~r/:conn.*fresh, unsent.*:unset/, fn ->
      start_session(:phoenix, conn: Plug.Conn.send_resp(build_conn(), 200, "already sent"))
    end

    error =
      assert_raise Fluffy.CapabilityError, ~r/^Playwright does not support :start_session \(:phoenix_conn\)/, fn ->
        start_session(:playwright,
          conn: build_conn()
        )
      end

    assert {error.backend, error.driver} == {:playwright, nil}
  end

  defp initial_session do
    start_session(:phoenix, conn: Plug.Conn.assign(build_conn(), :initial_principal, "chamber-keeper"))
  end
end
