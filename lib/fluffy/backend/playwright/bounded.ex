defmodule Fluffy.Backend.Playwright.Bounded do
  @moduledoc false

  # Some Playwright calls have no timeout of their own (`evaluate`, `content`,
  # closing): they wait while a script blocks the page's main thread.

  @doc """
  Runs a Playwright call that has no timeout of its own for at most `timeout` ms.

  The call runs unlinked, so a crash exits the caller with its reason instead of
  killing it.
  """
  def within(timeout, fun) do
    task = Task.Supervisor.async_nolink(Fluffy.TaskSupervisor, fun)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> {:ok, result}
      {:exit, reason} -> exit(reason)
      nil -> :timeout
    end
  end

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
