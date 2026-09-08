defmodule Fluffy.EctoSandboxConformanceTest do
  use ExUnit.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestRepo
  alias Fluffy.TestWeb.Endpoint

  setup_all do
    :ok = Fluffy.TestDatabase.ensure_started()
  end

  setup context do
    :ok = Fluffy.Test.setup(context, repos: [TestRepo])
    value = "record-#{System.unique_integer([:positive, :monotonic])}"

    TestRepo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")
    TestRepo.query!("INSERT INTO fluffy_records (value) VALUES ($1)", [value])

    [value: value]
  end

  for backend <- [:phoenix, :playwright] do
    @tag backend: backend
    test "shares one isolated transaction across Static and Live with #{backend}", %{
      backend: backend,
      value: value
    } do
      session =
        start_session(backend,
          base_url: Fluffy.TestServer.base_url(),
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

      assert_receive {:fluffy_test_sandbox_allow, TestRepo, child} when is_pid(child)
    end
  end

  test "uses the configured sandbox transport and allowance adapter" do
    assert Fluffy.Sandbox.header() == "user-agent"
    assert Fluffy.Sandbox.connect_info() == :user_agent
    assert Fluffy.Sandbox.allowance() == Fluffy.TestSandbox
  end

  test "two browser sessions share a sandbox but use isolated BrowserContexts", %{value: value} do
    first = browser_session()
    second = browser_session()

    refute Map.has_key?(first.context, :browser_id)
    refute Map.has_key?(second.context, :browser_id)
    refute first.context.context_id == second.context.context_id

    first |> visit("/database") |> expect(value |> by_text() |> to_be_visible())
    second |> visit("/database") |> expect(value |> by_text() |> to_be_visible())

    first |> visit("/database") |> expect(value |> by_text() |> to_be_visible())
    second |> visit("/database") |> expect(value |> by_text() |> to_be_visible())
  end

  defp browser_session do
    start_session(:playwright,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
  end
end

defmodule Fluffy.EctoSandboxAdoptionTest do
  use ExUnit.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Ecto.Adapters.SQL.Sandbox
  alias Fluffy.TestRepo
  alias Fluffy.TestScope
  alias Fluffy.TestWeb.Endpoint

  setup_all do
    :ok = Fluffy.TestDatabase.ensure_started()
  end

  test "adopts an existing sandbox checkout without starting another owner", context do
    :ok = Sandbox.checkout(TestRepo)
    on_exit(fn -> Sandbox.checkin(TestRepo) end)

    assert :ok = Fluffy.Test.setup(context, repos: [TestRepo])
    scope = TestScope.current()
    assert TestScope.status(scope).owners == []

    TestRepo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")
    TestRepo.query!("INSERT INTO fluffy_records (value) VALUES ('adopted')")

    :phoenix
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
    |> visit("/database")
    |> expect("Static values: adopted" |> by_text() |> to_be_visible())
  end

  test "adopts an existing sandbox allowance without starting another owner", context do
    owner = Sandbox.start_owner!(TestRepo)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    assert :ok = Fluffy.Test.setup(context, repos: [TestRepo])
    scope = TestScope.current()
    assert TestScope.status(scope).owners == []

    TestRepo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")
    TestRepo.query!("INSERT INTO fluffy_records (value) VALUES ('allowed')")

    :phoenix
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Endpoint
    )
    |> visit("/database")
    |> expect("Static values: allowed" |> by_text() |> to_be_visible())
  end
end
