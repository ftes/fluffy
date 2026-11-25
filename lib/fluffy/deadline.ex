defmodule Fluffy.Deadline do
  @moduledoc false

  # `timeout: :infinity` sets no deadline: it never expires and its remaining
  # time stays `:infinity`.
  @type t :: integer() | :infinity

  # `:once` has passed as it is set, so a retry makes one attempt.
  @spec new(Fluffy.Timeouts.t()) :: t()
  def new(:infinity), do: :infinity
  def new(:once), do: System.monotonic_time(:millisecond)
  def new(timeout) when is_integer(timeout) and timeout > 0, do: System.monotonic_time(:millisecond) + timeout

  # Browser bookkeeping can request a minimum of 1 to attempt a protocol call.
  # Event waits and retries use the default of 0.
  @spec remaining(t(), non_neg_integer()) :: timeout()
  def remaining(deadline, minimum \\ 0)
  def remaining(:infinity, _minimum), do: :infinity
  def remaining(deadline, minimum), do: max(deadline - System.monotonic_time(:millisecond), minimum)

  @spec expired?(t()) :: boolean()
  def expired?(deadline), do: remaining(deadline) == 0

  # The time left as a timeout: `:once` when none is left.
  @spec timeout(t()) :: Fluffy.Timeouts.t()
  def timeout(deadline) do
    case remaining(deadline) do
      0 -> :once
      timeout -> timeout
    end
  end

  # Sends `message` to `pid` when the deadline passes; with no deadline, never.
  @spec send_after(t(), pid(), term()) :: reference() | nil
  def send_after(:infinity, _pid, _message), do: nil
  def send_after(deadline, pid, message), do: Process.send_after(pid, message, remaining(deadline))

  # The Playwright timeout for a Fluffy one. Playwright's `0` is no timeout, so
  # `:once` becomes 1ms. Playwright maps `:infinity` to Playwright's `0`.
  @spec playwright(Fluffy.Timeouts.t()) :: pos_integer() | :infinity
  def playwright(:once), do: 1
  def playwright(timeout) when (is_integer(timeout) and timeout > 0) or timeout == :infinity, do: timeout

  # The Playwright timeout of an action or wait. An expectation can check once:
  # Playwright makes one check before its timeout applies. An action, wait or
  # locator read cannot, and would time out at 1ms, so it rejects `:once`
  # before reaching the browser.
  @spec playwright_operation!(atom(), Fluffy.Timeouts.t()) :: pos_integer() | :infinity
  def playwright_operation!(operation, :once) do
    raise ArgumentError,
          "#{operation}: timeout: :once checks once, which Playwright actions and waits can't do; " <>
            "pass a positive timeout or :infinity"
  end

  def playwright_operation!(_operation, timeout), do: playwright(timeout)
end
