defmodule Fluffy.EctoSandboxStressCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Fluffy.Support.Repo

  using do
    quote do
      use Fluffy.Test

      import Fluffy
      import Fluffy.Expect
      import Fluffy.Locator
    end
  end

  setup {Fluffy.Support.Case, :start_sandbox}

  setup do
    value = "stress-#{System.unique_integer([:positive, :monotonic])}"

    Repo.query!("CREATE TEMP TABLE fluffy_records (value text NOT NULL) ON COMMIT DROP")

    Repo.query!("INSERT INTO fluffy_records (value) VALUES ($1)", [value])
    [value: value]
  end
end

defmodule Fluffy.EctoSandboxStressOneTest do
  use Fluffy.EctoSandboxStressCase, async: true

  test("isolates browser request one", %{value: value}, do: assert_isolated(value))

  defp assert_isolated(value) do
    :playwright
    |> start_session(
      base_url: Fluffy.Support.Server.base_url(),
      endpoint: Fluffy.Support.Web.Endpoint
    )
    |> visit("/database")
    |> expect("Static values: #{value}" |> by_text(exact: true) |> to_have_count(1))
  end
end

defmodule Fluffy.EctoSandboxStressTwoTest do
  use Fluffy.EctoSandboxStressCase, async: true

  test("isolates browser request two", %{value: value}, do: assert_isolated(value))

  defp assert_isolated(value) do
    :playwright
    |> start_session(
      base_url: Fluffy.Support.Server.base_url(),
      endpoint: Fluffy.Support.Web.Endpoint
    )
    |> visit("/database")
    |> expect("Static values: #{value}" |> by_text(exact: true) |> to_have_count(1))
  end
end

defmodule Fluffy.EctoSandboxStressThreeTest do
  use Fluffy.EctoSandboxStressCase, async: true

  test("isolates browser request three", %{value: value}, do: assert_isolated(value))

  defp assert_isolated(value) do
    :playwright
    |> start_session(
      base_url: Fluffy.Support.Server.base_url(),
      endpoint: Fluffy.Support.Web.Endpoint
    )
    |> visit("/database")
    |> expect("Static values: #{value}" |> by_text(exact: true) |> to_have_count(1))
  end
end

defmodule Fluffy.EctoSandboxStressFourTest do
  use Fluffy.EctoSandboxStressCase, async: true

  test("isolates browser request four", %{value: value}, do: assert_isolated(value))

  defp assert_isolated(value) do
    :playwright
    |> start_session(
      base_url: Fluffy.Support.Server.base_url(),
      endpoint: Fluffy.Support.Web.Endpoint
    )
    |> visit("/database")
    |> expect("Static values: #{value}" |> by_text(exact: true) |> to_have_count(1))
  end
end
