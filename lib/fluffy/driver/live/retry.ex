defmodule Fluffy.Driver.Live.Retry do
  @moduledoc false

  alias Fluffy.Deadline
  alias Fluffy.Session

  # The deadline an operation's `:timeout` option, or the session default, sets.
  def deadline(%Session{} = session, options) when is_list(options) do
    options |> Keyword.get(:timeout, Session.context(session).timeout) |> Deadline.new()
  end

  def run(%Session{} = session, deadline, attempt, refresh, wait_for_retry)
      when (is_integer(deadline) or deadline == :infinity) and is_function(attempt, 1) and is_function(refresh, 1) and
             is_function(wait_for_retry, 2) do
    do_run(session, deadline, attempt, refresh, wait_for_retry)
  end

  def run_current(%Session{} = session, deadline, attempt, refresh, wait_for_retry)
      when (is_integer(deadline) or deadline == :infinity) and is_function(attempt, 1) and is_function(refresh, 1) and
             is_function(wait_for_retry, 2) do
    run_attempt(session, deadline, attempt, refresh, wait_for_retry)
  end

  defp do_run(session, deadline, attempt, refresh, wait_for_retry) do
    case refresh.(session) do
      {:navigate, session, navigation} ->
        {:redirected, session, navigation}

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
    remaining = Deadline.remaining(deadline)

    if remaining == 0 do
      raise_failure(failure)
    else
      wait_and_retry(session, deadline, attempt, refresh, wait_for_retry, remaining)
    end
  end

  defp wait_and_retry(session, deadline, attempt, refresh, wait_for_retry, remaining) do
    wait = if remaining == :infinity, do: 10, else: min(remaining, 10)

    case wait_for_retry.(session, wait) do
      {:navigate, session, navigation} ->
        {:redirected, session, navigation}

      %Session{} = session ->
        do_run(session, deadline, attempt, refresh, wait_for_retry)
    end
  end

  defp raise_failure({:strictness, locator, candidates}) do
    raise Fluffy.StrictnessError, locator: locator, candidates: candidates
  end

  defp raise_failure({:exception, exception}), do: raise(exception)

  defp raise_failure(message) when is_binary(message), do: raise(ExUnit.AssertionError, message: message)
end
