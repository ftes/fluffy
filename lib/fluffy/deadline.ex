defmodule Fluffy.Deadline do
  @moduledoc false

  @type t :: integer()

  @spec new(non_neg_integer()) :: t()
  def new(timeout), do: System.monotonic_time(:millisecond) + timeout

  # Browser bookkeeping can request a minimum of 1 to attempt a protocol call.
  # Event waits and retries use the default of 0.
  @spec remaining(t(), non_neg_integer()) :: non_neg_integer()
  def remaining(deadline, minimum \\ 0), do: max(deadline - System.monotonic_time(:millisecond), minimum)

  @spec expired?(t()) :: boolean()
  def expired?(deadline), do: remaining(deadline) == 0
end
