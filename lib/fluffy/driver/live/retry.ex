defmodule Fluffy.Driver.Live.Retry do
  @moduledoc false

  alias Fluffy.Session

  def run(%Session{} = session, options, attempt, refresh, wait_for_retry)
      when is_list(options) and is_function(attempt, 1) and is_function(refresh, 1) and is_function(wait_for_retry, 2) do
    timeout = Keyword.get(options, :timeout, session.context.timeout)
    deadline = System.monotonic_time(:millisecond) + timeout
    do_run(session, deadline, attempt, refresh, wait_for_retry, nil)
  end

  def run_current(%Session{} = session, options, attempt, refresh, wait_for_retry)
      when is_list(options) and is_function(attempt, 1) and is_function(refresh, 1) and is_function(wait_for_retry, 2) do
    timeout = Keyword.get(options, :timeout, session.context.timeout)
    deadline = System.monotonic_time(:millisecond) + timeout
    run_attempt(session, deadline, attempt, refresh, wait_for_retry)
  end

  defp do_run(session, deadline, attempt, refresh, wait_for_retry, _last_failure) do
    case refresh.(session) do
      {:navigate, session, navigation} ->
        retry_after_navigation(session, navigation, deadline)

      %Session{} = session ->
        run_attempt(session, deadline, attempt, refresh, wait_for_retry)
    end
  end

  defp run_attempt(session, deadline, attempt, refresh, wait_for_retry) do
    case attempt.(session) do
      {:ok, value} -> value
      {:retry, failure} -> retry_or_raise(session, deadline, attempt, refresh, wait_for_retry, failure)
    end
  end

  defp retry_or_raise(session, deadline, attempt, refresh, wait_for_retry, failure) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      raise_failure(failure)
    else
      wait_and_retry(session, deadline, attempt, refresh, wait_for_retry, failure, remaining)
    end
  end

  defp wait_and_retry(session, deadline, attempt, refresh, wait_for_retry, failure, remaining) do
    case wait_for_retry.(session, min(remaining, 10)) do
      {:navigate, session, navigation} ->
        retry_after_navigation(session, navigation, deadline)

      %Session{} = session ->
        do_run(session, deadline, attempt, refresh, wait_for_retry, failure)
    end
  end

  defp retry_after_navigation(session, navigation, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    {:navigate, session, navigation, {:retry, remaining}}
  end

  defp raise_failure({:strictness, locator, candidates}) do
    raise Fluffy.StrictnessError, locator: locator, candidates: candidates
  end

  defp raise_failure({:exception, exception}), do: raise(exception)

  defp raise_failure(message) when is_binary(message), do: raise(ExUnit.AssertionError, message: message)
end
