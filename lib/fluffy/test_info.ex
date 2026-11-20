defmodule Fluffy.TestInfo do
  @moduledoc false

  @doc """
  The calling test's `Playwright.Test.info/0`, also in its Tasks through `$callers`, or
  `:error` outside a registered test (`use Playwright.Test`), `setup_all` too, whose info has no
  `test_pid`.
  """
  @spec fetch() :: {:ok, map()} | :error
  def fetch do
    with true <- Playwright.Test.in_registered_scope?(),
         %{test_pid: _} = info <- Playwright.Test.info() do
      {:ok, info}
    else
      _none -> :error
    end
  end

  @doc """
  The calling test's `Playwright.Test.info/0`; raises outside a registered test, which every
  session needs. Upstream's `page` fixture raises in `beforeAll` too (`index.ts`).
  """
  @spec fetch!() :: map()
  def fetch! do
    case fetch() do
      {:ok, info} ->
        info

      :error ->
        raise RuntimeError,
              "a Fluffy session can only start and run while its test is running: in a test of a module " <>
                "with `use Playwright.Test` (its process, or one with it in $callers), not in its setup_all, " <>
                "as Playwright Test's \"page\" fixture is created on a per-test basis"
    end
  end
end
