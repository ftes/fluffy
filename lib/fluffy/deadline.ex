defmodule Fluffy.Deadline do
  @moduledoc false

  # `timeout: :infinity` sets no deadline: it never expires and its remaining
  # time stays `:infinity`.
  @type t :: integer() | :infinity

  @spec new(timeout()) :: t()
  def new(:infinity), do: :infinity
  def new(timeout), do: System.monotonic_time(:millisecond) + timeout

  # Browser bookkeeping can request a minimum of 1 to attempt a protocol call.
  # Event waits and retries use the default of 0.
  @spec remaining(t(), non_neg_integer()) :: timeout()
  def remaining(deadline, minimum \\ 0)
  def remaining(:infinity, _minimum), do: :infinity
  def remaining(deadline, minimum), do: max(deadline - System.monotonic_time(:millisecond), minimum)

  @spec expired?(t()) :: boolean()
  def expired?(deadline), do: remaining(deadline) == 0

  # Sends `message` to `pid` when the deadline passes; with no deadline, never.
  @spec send_after(t(), pid(), term()) :: reference() | nil
  def send_after(:infinity, _pid, _message), do: nil
  def send_after(deadline, pid, message), do: Process.send_after(pid, message, remaining(deadline))

  # The PlaywrightEx timeout for a Fluffy one. Playwright's `0` is no timeout, so
  # Fluffy's `0`, a single check, becomes 1ms. PlaywrightEx maps `:infinity` to
  # Playwright's `0`.
  @spec playwright(timeout()) :: pos_integer() | :infinity
  def playwright(0), do: 1
  def playwright(timeout) when (is_integer(timeout) and timeout > 0) or timeout == :infinity, do: timeout

  # The PlaywrightEx timeout of an action or wait. An expectation can check once:
  # Playwright makes one check before its timeout applies. An action, wait or
  # locator read cannot, and would time out at 1ms, so it rejects Fluffy's 0
  # before reaching the browser.
  @spec playwright_operation!(atom(), timeout()) :: pos_integer() | :infinity
  def playwright_operation!(operation, 0) do
    raise ArgumentError,
          "#{operation}: timeout: 0 means check once, which Playwright actions and waits can't do; " <>
            "pass a positive timeout or :infinity"
  end

  def playwright_operation!(_operation, timeout), do: playwright(timeout)
end
