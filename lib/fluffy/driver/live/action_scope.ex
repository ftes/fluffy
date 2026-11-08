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
  # An action's retries count the redirects they follow, so pages that keep
  # navigating before the action reaches them fail it at the redirect limit.
  #
  # Nothing checks that the driver records what this scope relies on, so Live
  # driver code that talks to a view must keep to these rules:
  #
  #   * A view call that sends the view something (an event, a patch, an
  #     upload) goes through `delivered/1` or `record_delivery/0`, so a
  #     retry never repeats an action the view already saw. Reads, such as
  #     `render`, record nothing.
  #   * A view message taken from the mailbox (a patch, a redirect, a watcher
  #     event) is passed to `record_taken/1` as it is taken, so a failed action
  #     puts it back. One the action then applies to its session goes to
  #     `record_applied/1`, and once the session left the page,
  #     `record_left_page/0` drops them all.
  #   * A retry on another page runs after the action's scope ended, as an
  #     action of its own, so it neither counts the first page's deliveries
  #     nor puts back its messages. It passes the redirects followed so far
  #     through `after_redirects/2`, so the redirect limit holds across retries.

  @scope {__MODULE__, :scope}
  @redirects {__MODULE__, :redirects}

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

  # Runs a retry on the page the action's `redirects`-th redirect landed on.
  def after_redirects(redirects, retry) when is_integer(redirects) and is_function(retry, 0) do
    previous = Process.put(@redirects, redirects)

    try do
      retry.()
    after
      restore(@redirects, previous)
    end
  end

  # The redirects the running action followed to the page it acts on.
  def redirects, do: Process.get(@redirects, 0)

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

  # Records that the action's session left the page it took the messages on,
  # so a failed action has none to put back.
  def record_left_page, do: update(&%{&1 | taken: []})

  defp update(fun) do
    case Process.get(@scope) do
      nil -> :ok
      scope -> Process.put(@scope, fun.(scope))
    end

    :ok
  end
end
