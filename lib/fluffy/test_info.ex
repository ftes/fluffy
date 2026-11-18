defmodule Fluffy.TestInfo do
  @moduledoc false

  @doc """
  The calling test's `Playwright.Test.info/0`, also in its Tasks through `$callers`, or
  `:error` outside a registered test (`use Playwright.Test`).
  """
  @spec fetch() :: {:ok, map()} | :error
  def fetch, do: if(Playwright.Test.in_registered_test?(), do: {:ok, Playwright.Test.info()}, else: :error)

  @doc "The calling test's `Playwright.Test.info/0`; raises outside a registered test, as every session needs one."
  @spec fetch!() :: map()
  def fetch! do
    case fetch() do
      {:ok, info} ->
        info

      :error ->
        raise RuntimeError,
              "a Fluffy session can only start while a test is running: in a test of a module with " <>
                "`use Playwright.Test` (its process, or one with it in $callers)"
    end
  end
end
