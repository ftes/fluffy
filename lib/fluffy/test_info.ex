defmodule Fluffy.TestInfo do
  @moduledoc false

  @doc """
  The calling test's `Playwright.Test.info/0`, also in its Tasks through `$callers`, or
  `:error` outside a registered test (`use Fluffy.Case`).
  """
  @spec fetch() :: {:ok, map()} | :error
  def fetch, do: if(Playwright.Test.in_registered_test?(), do: {:ok, Playwright.Test.info()}, else: :error)
end
