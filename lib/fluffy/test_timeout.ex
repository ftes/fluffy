defmodule Fluffy.TestTimeout do
  @moduledoc false

  # The test's ExUnit timeout, recorded in its setup by `Fluffy.Case.put_test_timeout/1`. Phoenix
  # sessions bound their waits by it (LiveView retries, event waits), so an operation without a
  # timeout fails with Fluffy's error just before ExUnit kills the test, at the moment PlaywrightEx.Test closes a Playwright
  # session's context (`PlaywrightEx.Test.Recorder.test_timeout_margin/1`, the same formula).
  # Kept by the test process, so its Tasks find it through `$callers` and it goes with the test.

  # ExUnit's clock started at the test process's spawn, before the setups: as PlaywrightEx.Test,
  # count from this one.
  @spec put(map()) :: :ok
  def put(context) do
    case timeout(context) do
      :infinity ->
        :ok

      timeout ->
        backstop = System.monotonic_time(:millisecond) + timeout - min(1000, div(timeout, 20))
        Registry.unregister(__MODULE__, self())
        {:ok, _owner} = Registry.register(__MODULE__, self(), {timeout, backstop})
        :ok
    end
  end

  # ExUnit's `get_timeout/2`: none under `--trace`, else the test's `timeout` tag or the config's.
  defp timeout(context) do
    config = ExUnit.configuration()
    if config[:trace], do: :infinity, else: Map.get(context, :timeout, config[:timeout])
  end

  @doc "The calling test's `{timeout, backstop}`, `nil` without one."
  @spec fetch() :: {pos_integer(), integer()} | nil
  def fetch do
    Enum.find_value([self() | Process.get(:"$callers", [])], fn pid ->
      case Registry.lookup(__MODULE__, pid) do
        [{_owner, value}] -> value
        [] -> nil
      end
    end)
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
