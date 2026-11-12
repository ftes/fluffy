defmodule Fluffy.EctoSandboxLifecycleTest do
  use ExUnit.Case, async: true
  use PlaywrightEx.Test

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Support.Case, only: [browser_context_guids: 1]

  alias Fluffy.Support.Repo
  alias Fluffy.Support.RepoTwo
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint
  alias Fluffy.TestScope

  setup_all do
    :ok = Fluffy.Support.Database.ensure_started()
  end

  test "propagates metadata for multiple repos", context do
    assert :ok = Fluffy.Test.setup(context, repos: [Repo, RepoTwo])
    assert length(TestScope.current().owners) == 2

    session =
      start_session(:playwright,
        base_url: Server.base_url(),
        endpoint: Endpoint
      )

    session
    |> visit("/databases")
    |> expect("Repos: #{database_name()}, #{database_name()}" |> by_text() |> to_be_visible())
  end

  @tag :capture_log
  test "teardown closes sessions before it stops sandbox owners", context do
    observer = start_exit_observer()
    # Registered before the setup's callbacks, so it runs after them.
    on_exit(fn ->
      {order, {browser_context, playwright_browser}} = exit_order(observer)
      assert List.last(order) == :owner
      refute browser_context.guid in browser_context_guids(playwright_browser)
    end)

    assert :ok = Fluffy.Test.setup(context, repos: [Repo])
    [owner] = TestScope.current().owners

    Repo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")
    Repo.query!("INSERT INTO fluffy_records (value) VALUES ('shutdown')")

    browser =
      :playwright
      |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
      |> visit("/live/database?delay=250")

    live = start_session(:phoenix, base_url: Server.base_url(), endpoint: Endpoint)
    {:ok, live_view} = Agent.start(fn -> nil end)
    :ok = Fluffy.Backend.Phoenix.register_process(live.runtime, :live_view, live_view, 100)

    # The context's browser is read now: it is closed by the time `on_exit` runs.
    browser_context = Fluffy.Session.context(browser).browser_context

    watch_exits(
      observer,
      %{browser.runtime => :browser, live_view => :live_view, owner => :owner},
      {browser_context, PlaywrightEx.BrowserContext.browser(browser_context)}
    )
  end

  # Records the order in which the watched processes exit, for an `on_exit` to read with `data`.
  defp start_exit_observer do
    spawn(fn ->
      receive do
        {:watch, from, names, data} ->
          references = Map.new(names, fn {pid, name} -> {Process.monitor(pid), name} end)
          send(from, :watching)

          order =
            for _name <- names, do: receive(do: ({:DOWN, reference, :process, _pid, _reason} -> references[reference]))

          receive do: ({:order, from} -> send(from, {:order, order, data}))
      end
    end)
  end

  defp watch_exits(observer, names, data) do
    send(observer, {:watch, self(), names, data})
    assert_receive :watching
  end

  defp exit_order(observer) do
    send(observer, {:order, self()})
    assert_receive {:order, order, data}, 5_000
    {order, data}
  end

  defp database_name do
    :fluffy |> Application.fetch_env!(Repo) |> Keyword.fetch!(:database)
  end
end

defmodule Fluffy.EctoSandboxSharedModeTest do
  use ExUnit.Case, async: false
  use PlaywrightEx.Test

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Ecto.Adapters.SQL.Sandbox
  alias Fluffy.Support.Repo
  alias Fluffy.TestScope

  setup_all do
    :ok = Fluffy.Support.Database.ensure_started()
  end

  test "adopts an existing shared sandbox and supports multiple sessions", context do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    assert :ok = Fluffy.Test.setup(context, repos: [Repo])
    assert TestScope.current().owners == []

    Repo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")
    Repo.query!("INSERT INTO fluffy_records (value) VALUES ('shared')")

    first = browser_session()
    second = browser_session()

    first |> visit("/database") |> expect("Static values: shared" |> by_text() |> to_be_visible())
    second |> visit("/database") |> expect("Static values: shared" |> by_text() |> to_be_visible())
  end

  defp browser_session do
    start_session(:playwright,
      base_url: Fluffy.Support.Server.base_url(),
      endpoint: Fluffy.Support.Web.Endpoint
    )
  end
end
