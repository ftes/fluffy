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
    outcome(Task.yield(task, timeout) || stop(task, on_timeout))
  end

  @doc """
  Like `within/3`, but a `{ref, tag, value}` message arriving first kills the
  call and returns `{:message, value}`.
  """
  def within_unless(timeout, fun, {ref, tag}) do
    task = Task.Supervisor.async_nolink(Fluffy.TaskSupervisor, fun)
    task_ref = task.ref

    received =
      receive do
        {^task_ref, result} ->
          Task.ignore(task)
          {:ok, result}

        {:DOWN, ^task_ref, :process, _pid, reason} ->
          {:exit, reason}

        {^ref, ^tag, value} ->
          Task.shutdown(task, :brutal_kill)
          {:message, value}
      after
        timeout -> stop(task, :kill)
      end

    outcome(received)
  end

  defp outcome({:ok, result}), do: {:ok, result}
  defp outcome({:message, value}), do: {:message, value}
  defp outcome({:exit, {exception, stacktrace}}) when is_exception(exception), do: reraise(exception, stacktrace)
  defp outcome({:exit, reason}), do: exit(reason)
  defp outcome(nil), do: :timeout

  defp stop(task, :kill), do: Task.shutdown(task, :brutal_kill)
  defp stop(task, :leave), do: Task.ignore(task)

  @doc """
  Like `within/2` for a call returning `{:ok, value}` or `{:error, error}`; returns the value or raises.

  On timeout it runs the `after_timeout:` function, if any, then raises with
  `message:` or a default naming `operation`.
  """
  def within!(timeout, operation, fun, options \\ []) do
    options = Keyword.validate!(options, [:message, after_timeout: fn -> :ok end])

    case within(timeout, fun) do
      {:ok, {:ok, value}} ->
        value

      {:ok, {:error, error}} ->
        raise error

      :timeout ->
        options[:after_timeout].()

        raise options[:message] ||
                "Playwright #{operation} did not finish within #{timeout}ms; " <>
                  "it may never settle, or a script may be blocking the page's main thread"
    end
  end
end
