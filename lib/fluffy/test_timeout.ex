defmodule Fluffy.TestTimeout do
  @moduledoc false

  # The backstop of Fluffy's own waits (LiveView retries, event waits on every driver): an
  # operation without a timeout fails with Fluffy's error just before ExUnit kills the test, at
  # the moment Playwright.Test closes the test's contexts, so a Playwright call fails
  # (`deadline` of `Playwright.Test.info/0`). It comes from the test's registration
  # (`use Playwright.Test`), also in its Tasks, through `$callers`. Without one, as in a process
  # outside the test, there is no backstop.

  @doc "The calling test's `{timeout, backstop}`, `nil` without one."
  @spec fetch() :: {pos_integer(), integer()} | nil
  def fetch do
    case Fluffy.TestInfo.fetch() do
      {:ok, %{timeout: timeout, deadline: backstop}} when is_integer(timeout) and is_integer(backstop) ->
        {timeout, backstop}

      _none ->
        nil
    end
  end

  @doc "`deadline`, bounded by the test's backstop."
  @spec bound(Fluffy.Deadline.t()) :: Fluffy.Deadline.t()
  def bound(deadline) do
    case {fetch(), deadline} do
      {nil, deadline} -> deadline
      {{_timeout, backstop}, :infinity} -> backstop
      {{_timeout, backstop}, deadline} -> min(deadline, backstop)
    end
  end

  @doc """
  A failure at `deadline`, with Playwright's reason first when the test's backstop was the
  deadline: an exception with a `message`, or a message.
  """
  @spec explain(exception | String.t(), Fluffy.Deadline.t()) :: exception | String.t() when exception: Exception.t()
  def explain(failure, deadline) do
    case fetch() do
      {timeout, ^deadline} -> prepend(failure, "Test timeout of #{timeout}ms exceeded.\n")
      _other -> failure
    end
  end

  defp prepend(message, reason) when is_binary(message), do: reason <> message

  defp prepend(%{message: message} = exception, reason) when is_binary(message),
    do: %{exception | message: reason <> message}
end
