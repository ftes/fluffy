defmodule Fluffy.Event.Pending do
  @moduledoc "An opaque, single-use pending event returned by `Fluffy.wait_for/3`."
  @enforce_keys [:pid]
  defstruct [:pid]
  @opaque t :: %__MODULE__{pid: pid()}

  @doc false
  @spec new(pid()) :: t()
  def new(pid), do: %__MODULE__{pid: pid}

  @doc false
  @spec cancel(t()) :: :ok
  def cancel(%__MODULE__{pid: pid}), do: Fluffy.Event.Subscription.cancel(pid)

  @doc false
  @spec await(t()) :: term()
  def await(%__MODULE__{pid: pid}) do
    case GenServer.call(pid, :await, :infinity) do
      {:ok, value} -> value
      {:raise, kind, reason, stacktrace} -> :erlang.raise(kind, reason, stacktrace)
      {:error, message} -> raise ExUnit.AssertionError, message: message
    end
  catch
    :exit, {:noproc, _} -> raise ArgumentError, "pending event was already consumed or its owner exited"
    :exit, {:normal, _} -> raise ArgumentError, "pending event was already consumed or its owner exited"
  end
end
