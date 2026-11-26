defmodule Fluffy.EctoSandboxConformanceTest do
  use ExUnit.Case, async: true
  use Playwright.Test

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Ecto.Adapters.SQL.Sandbox
  alias Fluffy.Event
  alias Fluffy.Support.Repo
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  setup {Fluffy.Support.Case, :start_sandbox}

  setup do
    value = "record-#{System.unique_integer([:positive, :monotonic])}"

    Repo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")
    Repo.query!("INSERT INTO fluffy_records (value) VALUES ($1)", [value])

    [value: value]
  end

  test "a Playwright route handler runs inside the test's sandbox", %{value: value} do
    session = start_session(:playwright, base_url: Server.base_url(), endpoint: Endpoint)

    Fluffy.Playwright.route(session, "**/fluffy-sandbox-route", fn route ->
      %{rows: [[read]]} = Repo.query!("SELECT value FROM fluffy_records")
      Playwright.Route.fulfill!(route, json: %{value: read})
    end)

    session = visit(session, "/database")

    assert Fluffy.Playwright.evaluate(
             session,
             "url => fetch(url).then(response => response.json())",
             Server.base_url() <> "/fluffy-sandbox-route"
           ) == %{"value" => value}
  end

  test "event handlers and wait predicates run inside the test's sandbox", %{value: value} do
    test = self()
    read = fn -> Repo.query!("SELECT value FROM fluffy_records").rows end
    session = start_session(:playwright, base_url: Server.base_url(), endpoint: Endpoint)

    on(session, Event.console(), fn _message -> send(test, {:handled, read.()}) end)
    wait = wait_for(session, Event.console(fn _message -> read.() == [[value]] end))
    Fluffy.Playwright.evaluate(session, "() => console.log('Hedwig')")

    assert %Playwright.ConsoleMessage{} = await(wait)
    assert_receive {:handled, [[^value]]}
  end

  test "a session a Task of the test starts belongs to the test and its sandbox", %{value: value} do
    session = Task.await(Task.async(fn -> start_session(:playwright, base_url: Server.base_url()) end))

    # The Task is gone; the session closes with the test.
    on_exit(fn ->
      monitor = Process.monitor(session.runtime)
      assert_receive {:DOWN, ^monitor, :process, _runtime, _reason}, 5_000
    end)

    session
    |> visit("/database")
    |> expect("Static values: #{value}" |> by_text() |> to_be_visible())
  end

  test "a Phoenix session in a Task of the test uses its sandbox", %{value: value} do
    Task.await(
      Task.async(fn ->
        :phoenix
        |> start_session(endpoint: Endpoint)
        |> visit("/database")
        |> expect("Static values: #{value}" |> by_text() |> to_be_visible())
      end)
    )
  end

  test "a request after set_extra_http_headers still reaches the sandboxed connection", %{value: value} do
    :playwright
    |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
    |> Fluffy.Playwright.set_extra_http_headers(%{"x-fluffy-extra" => "1"})
    |> visit("/database")
    |> expect("Static values: #{value}" |> by_text() |> to_be_visible())
  end

  for backend <- [:phoenix, :playwright] do
    @tag backend: backend
    test "shares one isolated transaction across Static and Live with #{backend}", %{
      backend: backend,
      value: value
    } do
      session =
        start_session(backend,
          base_url: Server.base_url(),
          endpoint: Endpoint
        )

      session
      |> visit("/database")
      |> expect("Static values: #{value}" |> by_text() |> to_be_visible())
      |> click(by_role(:link, name: "Open database LiveView", exact: true))
      |> expect("Live values: #{value}" |> by_text() |> to_be_visible())
      |> expect("Component count: 1" |> by_text() |> to_be_visible())
      |> expect("Async count: 1" |> by_text() |> to_be_visible(), timeout: 1_000)
      |> expect("Delayed count: 1" |> by_text() |> to_be_visible(), timeout: 1_000)
      |> expect("Nested count: 1" |> by_text() |> to_be_visible(), timeout: 1_000)
      |> click(by_role(:button, name: "Insert event", exact: true))
      |> expect("Live values: event, #{value}" |> by_text() |> to_be_visible())
      |> expect("Component count: 2" |> by_text() |> to_be_visible())
      |> click(by_role(:link, name: "Back to database page", exact: true))
      |> expect("Static values: event, #{value}" |> by_text() |> to_be_visible())

      if backend == :playwright do
        assert_receive {:fluffy_test_sandbox_allow, Repo, child} when is_pid(child)
      else
        # In-process requests and LiveViews use the sandbox through `$callers`, as with ConnTest.
        refute_received {:fluffy_test_sandbox_allow, _repo, _child}
      end
    end
  end

  test "Phoenix requests run no sandbox allowance in the test process", %{value: value} do
    Process.flag(:trap_exit, false)

    :phoenix
    |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
    |> visit("/database")
    |> expect("Static values: #{value}" |> by_text() |> to_be_visible())

    assert Process.info(self(), :trap_exit) == {:trap_exit, false}
  end

  for {hook, path} <- [{"Fluffy.Sandbox", "/live/lumos"}, {"a hook passing Fluffy.Sandbox", "/live/lumos-own-hook"}] do
    test "the sandbox owner outlasts a LiveView allowed by #{hook}", %{sandbox_owners: [owner | _]} do
      # Runs after the session's `on_exit` and before the owner stops: the LiveView's
      # `terminate/2` ran and reached the owner's connection.
      on_exit(fn ->
        :ok = Sandbox.allow(Repo, owner, self())
        assert Repo.query!("SELECT value FROM fluffy_records WHERE value = 'Nox'").rows == [["Nox"]]
      end)

      :playwright
      |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
      |> visit(unquote(path))
      |> expect("Lumos" |> by_text() |> to_be_visible())

      assert_receive {:fluffy_test_sandbox_allow, Repo, _child}
    end
  end

  test "the test waits for the LiveView a hook allowed, not for the static render's request" do
    :playwright
    |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
    |> visit("/live/lumos-own-hook")
    |> expect("Lumos" |> by_text() |> to_be_visible())

    # The endpoint plug and the hook's static render allow the request process first.
    {live_view, [_ | _] = requests} = allowed_until_live_view([])

    assert Registry.keys(Fluffy.Sandbox.Registry, live_view) == [self()]
    for request <- requests, do: assert(Registry.keys(Fluffy.Sandbox.Registry, request) == [])
  end

  test "uses the configured sandbox transport and allowance adapter" do
    assert Fluffy.Sandbox.header() == "user-agent"
    assert Fluffy.Sandbox.connect_info() == :user_agent
    assert Fluffy.Sandbox.allowance() == Fluffy.Support.Sandbox
  end

  test "two browser sessions share a sandbox but use isolated BrowserContexts", %{value: value} do
    first = browser_session()
    second = browser_session()

    refute Map.has_key?(Fluffy.Session.context(first), :browser_id)
    refute Map.has_key?(Fluffy.Session.context(second), :browser_id)
    refute Fluffy.Session.context(first).browser_context == Fluffy.Session.context(second).browser_context

    first |> visit("/database") |> expect(value |> by_text() |> to_be_visible())
    second |> visit("/database") |> expect(value |> by_text() |> to_be_visible())

    first |> visit("/database") |> expect(value |> by_text() |> to_be_visible())
    second |> visit("/database") |> expect(value |> by_text() |> to_be_visible())
  end

  defp allowed_until_live_view(requests) do
    assert_receive {:fluffy_test_sandbox_allow, Repo, child}

    if Phoenix.LiveView.Debug.liveview_process?(child),
      do: {child, requests},
      else: allowed_until_live_view([child | requests])
  end

  defp browser_session do
    start_session(:playwright,
      base_url: Server.base_url(),
      endpoint: Endpoint
    )
  end
end
