defmodule Fluffy.Driver.Live.ActionScope do
  @moduledoc false

  # What the running Live action did to its view. The driver's `act` runs each
  # action in a scope, which records whether one of its events reached the
  # view, so an action whose later call finds the view gone still counts the
  # events that reached it before, and the view messages, such as a redirect,
  # it took from the mailbox. An action that fails leaves its session on the
  # page it started on, so the scope puts those messages back for that
  # session's next call to find, except a patch the action already applied
  # there. Outside an action, recording does nothing.
  #
  # An action whose timeout ran out before it reached the view retries once on
  # the page a navigation landed on, as a final attempt that may not retry
  # again.

  @scope {__MODULE__, :scope}
  @final_attempt {__MODULE__, :final_attempt}

  def run(action) when is_function(action, 0) do
    previous = Process.put(@scope, %{delivered?: false, taken: []})

    try do
      action.()
    catch
      kind, reason ->
        @scope |> Process.get() |> Map.fetch!(:taken) |> put_back()
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      restore(@scope, previous)
    end
  end

  def final_attempt(retry) when is_function(retry, 0) do
    previous = Process.put(@final_attempt, true)

    try do
      retry.()
    after
      restore(@final_attempt, previous)
    end
  end

  # Puts the taken messages back ahead of those of the same kind that arrived
  # since, so later reads see them in the order the view sent them.
  defp put_back(taken) do
    taken
    |> Enum.reverse()
    |> Enum.group_by(&message_kind/1)
    |> Enum.each(fn {kind, messages} -> Enum.each(messages ++ take_queued(kind, []), &send(self(), &1)) end)
  end

  defp message_kind({:fluffy_live_view, watcher, _event}), do: {:watcher, watcher}
  defp message_kind({reference, {kind, topic, _options}}) when kind in [:patch, :redirect], do: {kind, reference, topic}

  defp take_queued({:watcher, watcher} = kind, queued) do
    receive do
      {:fluffy_live_view, ^watcher, _event} = message -> take_queued(kind, [message | queued])
    after
      0 -> Enum.reverse(queued)
    end
  end

  defp take_queued({tag, reference, topic} = kind, queued) do
    receive do
      {^reference, {^tag, ^topic, _options}} = message -> take_queued(kind, [message | queued])
    after
      0 -> Enum.reverse(queued)
    end
  end

  defp restore(key, nil), do: Process.delete(key)
  defp restore(key, previous), do: Process.put(key, previous)

  def final_attempt?, do: Process.get(@final_attempt) == true

  def delivered?, do: match?(%{delivered?: true}, Process.get(@scope))

  def record_delivery, do: update(&%{&1 | delivered?: true})

  # Records a view call that sent the view an event, patch or upload, and
  # passes its result on.
  def delivered(result) do
    record_delivery()
    result
  end

  def record_taken(message), do: update(&%{&1 | taken: [message | &1.taken]})

  # Records that the action applied a taken message to its session, so a
  # failed action leaves it out instead of applying it again.
  def record_applied(message), do: update(&%{&1 | taken: List.delete(&1.taken, message)})

  defp update(fun) do
    case Process.get(@scope) do
      nil -> :ok
      scope -> Process.put(@scope, fun.(scope))
    end

    :ok
  end
end
