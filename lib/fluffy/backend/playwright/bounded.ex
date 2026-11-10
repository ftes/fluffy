defmodule Fluffy.Backend.Playwright.Bounded do
  @moduledoc false

  # Fluffy's own reads around an operation (document probes, failure artifacts,
  # browser shutdown) must not hang on a page whose main thread a script blocks.
  # The Playwright calls they use (`evaluate`, `content`, closing) have no timeout
  # of their own; user-facing calls keep Playwright's behavior and are not bounded.

  @doc """
  Runs a Playwright call that has no timeout of its own for at most `timeout` ms.

  The call runs unlinked, so a crash does not kill the caller: an exception is
  raised again in the caller, any other crash exits it with its reason. A call
  still running after `timeout` is killed.
  """
  def within(timeout, fun) do
    task = Task.Supervisor.async_nolink(Fluffy.TaskSupervisor, fun)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> {:ok, result}
      {:exit, {exception, stacktrace}} when is_exception(exception) -> reraise exception, stacktrace
      {:exit, reason} -> exit(reason)
      nil -> :timeout
    end
  end
end
