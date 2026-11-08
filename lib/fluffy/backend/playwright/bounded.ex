defmodule Fluffy.Backend.Playwright.Bounded do
  @moduledoc false

  # Some Playwright calls have no timeout of their own (`evaluate`, `content`,
  # closing): they wait while a script blocks the page's main thread.

  @doc """
  Runs a Playwright call that has no timeout of its own for at most `timeout` ms.

  The call runs unlinked, so a crash does not kill the caller: an exception is
  raised again in the caller, any other crash exits it with its reason.

  A call still running after `timeout` is killed, or with `on_timeout: :leave`
  left to finish on its own.
  """
  def within(timeout, fun, options \\ []) do
    on_timeout = Keyword.validate!(options, on_timeout: :kill)[:on_timeout]
    task = Task.Supervisor.async_nolink(Fluffy.TaskSupervisor, fun)

    case Task.yield(task, timeout) || stop(task, on_timeout) do
      {:ok, result} -> {:ok, result}
      {:exit, {exception, stacktrace}} when is_exception(exception) -> reraise exception, stacktrace
      {:exit, reason} -> exit(reason)
      nil -> :timeout
    end
  end

  defp stop(task, :kill), do: Task.shutdown(task, :brutal_kill)
  defp stop(task, :leave), do: Task.ignore(task)

  @doc "Like `within/2` for a call returning `{:ok, value}` or `{:error, error}`; returns the value or raises."
  def within!(timeout, operation, fun) do
    case within(timeout, fun) do
      {:ok, {:ok, value}} ->
        value

      {:ok, {:error, error}} ->
        raise error

      :timeout ->
        raise "Playwright #{operation} did not finish within #{timeout}ms; " <>
                "it may never settle, or a script may be blocking the page's main thread"
    end
  end
end
