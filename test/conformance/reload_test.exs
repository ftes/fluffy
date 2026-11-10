defmodule Fluffy.Conformance.ReloadTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "reloads the current document and preserves the URL with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html("<h1>First render</h1>")},
          %{body: html("<h1>Second render</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture))
      |> expect("First render" |> by_text() |> to_be_visible())
      |> reload()
      |> expect("Second render" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(TestHTTPFixtures.url(fixture)))

      assert length(TestHTTPFixtures.requests(fixture)) == 2
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "reload with timeout: 0 reloads on Phoenix and is rejected on Playwright with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html("<h1>First render</h1>")},
          %{body: html("<h1>Second render</h1>")}
        ])

      session = driver |> start_test_session() |> visit(TestHTTPFixtures.path(fixture))

      if driver == :phoenix do
        session
        |> reload(timeout: 0)
        |> expect("Second render" |> by_text() |> to_be_visible())
      else
        for {operation, call} <- [
              reload: &reload(&1, timeout: 0),
              go_back: &Fluffy.Playwright.go_back(&1, timeout: 0),
              go_forward: &Fluffy.Playwright.go_forward(&1, timeout: 0)
            ] do
          assert_raise ArgumentError, ~r/^#{operation}: timeout: 0 means check once/, fn -> call.(session) end
        end

        assert length(TestHTTPFixtures.requests(fixture)) == 1
      end
    end
  end

  @tag driver: :playwright
  test "Playwright reload passes wait_until: through and still adopts the new document" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{body: html("<h1>First render</h1>")},
        %{body: html("<h1>Second render</h1>")}
      ])

    session = :playwright |> start_test_session() |> visit(TestHTTPFixtures.path(fixture))

    session
    |> reload(wait_until: :commit)
    |> expect("Second render" |> by_text() |> to_be_visible())

    for option <- [no_wait_after: true, signal: nil] do
      assert_raise NimbleOptions.ValidationError, fn -> reload(session, [option]) end
    end
  end

  @tag driver: :playwright
  test "a Playwright reload that never loads raises PlaywrightEx's timeout error" do
    owner = self()

    fixture =
      TestHTTPFixtures.register_sequence([
        %{body: html("<h1>First render</h1>")},
        %{
          stream: fn conn ->
            {:ok, conn} = Plug.Conn.chunk(conn, "<!doctype html><html><body><h1>Loading")

            send(owner, {:stream, self()})

            receive do
              :finish -> conn
            after
              30_000 -> conn
            end
          end
        }
      ])

    session = :playwright |> start_test_session() |> visit(TestHTTPFixtures.path(fixture))

    try do
      error = assert_raise Fluffy.OperationError, ~r/reload/, fn -> reload(session, timeout: 500) end
      assert %Fluffy.OperationError{operation: :reload, locator: nil, cause: %PlaywrightEx.TimeoutError{}} = error
    after
      receive do
        {:stream, server} -> send(server, :finish)
      after
        0 -> :ok
      end
    end
  end

  # Each LiveView sleeps 1s in its connected mount before it subscribes.
  @tag driver: :playwright
  test "Playwright reload's timeout: bounds the reload, not the LiveView connection wait after it" do
    topic = "reload-ready-#{System.unique_integer([:positive])}"

    session =
      :playwright
      |> start_test_session()
      |> visit("/embedded-ready?topic=#{topic}&delay=1000")
      |> reload(wait_until: :commit, timeout: 500)

    :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, topic, {:redirect_ready, "connected"})
    expect(session, "Broadcast: connected" |> by_text(exact: true) |> Fluffy.Expect.to_have_count(2))
  end

  @tag driver: :phoenix
  test "Phoenix reload raises a capability error for wait_until:" do
    fixture = TestHTTPFixtures.register_sequence([%{body: html("<h1>First render</h1>")}])
    session = :phoenix |> start_test_session() |> visit(TestHTTPFixtures.path(fixture))

    error =
      assert_raise Fluffy.CapabilityError, ~r/:wait_until is a Playwright option/, fn ->
        reload(session, wait_until: :load)
      end

    assert error.capability == :playwright_action_options
    assert length(TestHTTPFixtures.requests(fixture)) == 1
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end
