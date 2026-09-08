defmodule Fluffy.EctoSandboxStressCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Fluffy
      import Fluffy.Expect
      import Fluffy.Locator
    end
  end

  setup context do
    :ok = Fluffy.TestDatabase.ensure_started()
    :ok = Fluffy.Test.setup(context, repos: [Fluffy.TestRepo])
    value = "stress-#{System.unique_integer([:positive, :monotonic])}"

    Fluffy.TestRepo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")

    Fluffy.TestRepo.query!("INSERT INTO fluffy_records (value) VALUES ($1)", [value])
    [value: value]
  end
end

defmodule Fluffy.EctoSandboxStressOneTest do
  use Fluffy.EctoSandboxStressCase, async: true

  test("isolates browser request one", %{value: value}, do: assert_isolated(value))

  defp assert_isolated(value) do
    :playwright
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
    |> visit("/database")
    |> expect(count(by_text("Static values: #{value}", exact: true), 1))
  end
end

defmodule Fluffy.EctoSandboxStressTwoTest do
  use Fluffy.EctoSandboxStressCase, async: true

  test("isolates browser request two", %{value: value}, do: assert_isolated(value))

  defp assert_isolated(value) do
    :playwright
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
    |> visit("/database")
    |> expect(count(by_text("Static values: #{value}", exact: true), 1))
  end
end

defmodule Fluffy.EctoSandboxStressThreeTest do
  use Fluffy.EctoSandboxStressCase, async: true

  test("isolates browser request three", %{value: value}, do: assert_isolated(value))

  defp assert_isolated(value) do
    :playwright
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
    |> visit("/database")
    |> expect(count(by_text("Static values: #{value}", exact: true), 1))
  end
end

defmodule Fluffy.EctoSandboxStressFourTest do
  use Fluffy.EctoSandboxStressCase, async: true

  test("isolates browser request four", %{value: value}, do: assert_isolated(value))

  defp assert_isolated(value) do
    :playwright
    |> start_session(
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
    |> visit("/database")
    |> expect(count(by_text("Static values: #{value}", exact: true), 1))
  end
end
