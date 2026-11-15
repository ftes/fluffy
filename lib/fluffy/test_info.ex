defmodule Fluffy.TestInfo do
  @moduledoc false

  @doc """
  The calling test's `PlaywrightEx.Test.info/0`, also in its Tasks through `$callers`, or
  `:error` outside a registered test (`use Fluffy.Case`).
  """
  @spec fetch() :: {:ok, map()} | :error
  def fetch do
    {:ok, PlaywrightEx.Test.info()}
  rescue
    # Its error outside a registered test; any other passes through.
    error in RuntimeError ->
      if String.starts_with?(error.message, "PlaywrightEx.Test.info() can only be called while a test is running"),
        do: :error,
        else: reraise(error, __STACKTRACE__)
  end
end
