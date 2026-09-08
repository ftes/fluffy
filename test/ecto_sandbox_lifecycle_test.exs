defmodule Fluffy.EctoSandboxLifecycleTest do
  use ExUnit.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestRepo
  alias Fluffy.TestRepoTwo
  alias Fluffy.TestScope
  alias Fluffy.TestWeb.Endpoint
  alias PlaywrightEx.BrowserContext

  setup_all do
    :ok = Fluffy.TestDatabase.ensure_started()
  end

  test "propagates metadata for multiple repos", context do
    assert :ok = Fluffy.Test.setup(context, repos: [TestRepo, TestRepoTwo])
    scope = TestScope.current()

    assert length(TestScope.status(scope).owners) == 2

    session =
      start_session(:playwright,
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Endpoint
      )

    session
    |> visit("/databases")
    |> expect("Repos: #{database_name()}, #{database_name()}" |> by_text() |> to_be_visible())
  end

  @tag :capture_log
  test "scope shutdown closes browser contexts before sandbox owners", context do
    assert :ok = Fluffy.Test.setup(context, repos: [TestRepo])
    scope = TestScope.current()
    [owner] = TestScope.status(scope).owners

    TestRepo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")
    TestRepo.query!("INSERT INTO fluffy_records (value) VALUES ('shutdown')")

    session =
      :playwright
      |> start_session(
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Endpoint
      )
      |> visit("/live/database?delay=250")

    context_id = session.context.context_id
    GenServer.stop(scope)

    refute Process.alive?(owner)
    assert {:error, _reason} = BrowserContext.cookies(context_id, timeout: 100)
  end

  @tag :capture_log
  test "a sandbox owner crash closes the scope's browser resources", context do
    assert :ok = Fluffy.Test.setup(context, repos: [TestRepo])
    scope = TestScope.current()
    [owner] = TestScope.status(scope).owners

    session =
      start_session(:playwright,
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Endpoint
      )

    context_id = session.context.context_id
    scope_reference = Process.monitor(scope)
    Process.exit(owner, :kill)

    assert_receive {:DOWN, ^scope_reference, :process, ^scope, {:shutdown, {:sandbox_owner_down, :killed}}},
                   1_000

    assert {:error, _reason} = BrowserContext.cookies(context_id, timeout: 100)
  end

  test "supervisor shutdown drains Live resources before stopping sandbox ownership" do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(TestRepo)
    {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)

    {:ok, scope} =
      DynamicSupervisor.start_child(
        supervisor,
        {TestScope, owners: [owner], sandbox_header: nil, test_context: %{}, timeout: 100}
      )

    {_scope, session_id, _header} = TestScope.attach_session(scope)
    live_view = spawn(fn -> Process.sleep(:infinity) end)
    :ok = TestScope.register_live_view(scope, session_id, live_view)

    owner_reference = Process.monitor(owner)
    view_reference = Process.monitor(live_view)
    Supervisor.stop(supervisor)

    assert_receive {:DOWN, ^view_reference, :process, ^live_view, :shutdown}, 1_000
    assert_receive {:DOWN, ^owner_reference, :process, ^owner, :normal}, 1_000
  end

  defp database_name do
    :fluffy |> Application.fetch_env!(TestRepo) |> Keyword.fetch!(:database)
  end
end

defmodule Fluffy.EctoSandboxSharedModeTest do
  use ExUnit.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Ecto.Adapters.SQL.Sandbox
  alias Fluffy.TestRepo
  alias Fluffy.TestScope

  setup_all do
    :ok = Fluffy.TestDatabase.ensure_started()
  end

  test "adopts an existing shared sandbox and supports multiple sessions", context do
    owner = Sandbox.start_owner!(TestRepo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    assert :ok = Fluffy.Test.setup(context, repos: [TestRepo])
    scope = TestScope.current()
    assert TestScope.status(scope).owners == []

    TestRepo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")
    TestRepo.query!("INSERT INTO fluffy_records (value) VALUES ('shared')")

    first = browser_session()
    second = browser_session()

    first |> visit("/database") |> expect("Static values: shared" |> by_text() |> to_be_visible())
    second |> visit("/database") |> expect("Static values: shared" |> by_text() |> to_be_visible())
  end

  defp browser_session do
    start_session(:playwright,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end
end
