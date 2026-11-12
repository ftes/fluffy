defmodule Fluffy.Driver.Live.Retry do
  @moduledoc false

  alias Fluffy.Deadline
  alias Fluffy.Session
  alias Fluffy.TestTimeout

  # The deadline of an operation's timeout, its `timeout:` or its default
  # (`Fluffy.Timeouts`), bounded by the test's (`Fluffy.TestTimeout`): a retry without a limit
  # fails with Fluffy's error before ExUnit's timeout, as a Playwright call does when
  # PlaywrightEx.Test closes its context then. Without either, it goes on until ExUnit's.
  def deadline(timeout), do: timeout |> Deadline.new() |> TestTimeout.bound()

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
      failure |> exception() |> TestTimeout.explain(deadline) |> raise()
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

  defp exception({:strictness, locator, candidates}),
    do: Fluffy.StrictnessError.exception(locator: locator, candidates: candidates)

  defp exception({:exception, exception}), do: exception
  defp exception(message) when is_binary(message), do: ExUnit.AssertionError.exception(message: message)
end
