defmodule Fluffy.TestInfo do
  @moduledoc false

  @doc """
  The calling test's `PlaywrightEx.Test.info/0`, also in its Tasks through `$callers`, or
  `:error` outside a registered test (`use Fluffy.Case`).
  """
  @spec fetch() :: {:ok, map()} | :error
  def fetch, do: if(PlaywrightEx.Test.in_registered_test?(), do: {:ok, PlaywrightEx.Test.info()}, else: :error)
end
