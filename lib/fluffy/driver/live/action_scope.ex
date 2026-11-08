defmodule Fluffy.Driver.Live.ActionScope do
  @moduledoc false

  # What the running Live action did to its view. The driver's `act` runs each
  # action in a scope, which records whether one of its events reached the
  # view, so an action whose later call finds the view gone still counts the
  # events that reached it before, and the view messages, such as a redirect,
  # it took from the mailbox. An action that fails leaves its session on the
  # page it started on, so the scope puts those messages back for that
  # session's next call to find. Outside an action, recording does nothing.

  @scope {__MODULE__, :scope}

  def run(action) when is_function(action, 0) do
    Process.put(@scope, %{delivered?: false, taken: []})

    try do
      action.()
    catch
      kind, reason ->
        @scope |> Process.get() |> Map.fetch!(:taken) |> Enum.reverse() |> Enum.each(&send(self(), &1))
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      Process.delete(@scope)
    end
  end

  def delivered?, do: match?(%{delivered?: true}, Process.get(@scope))

  def record_delivery, do: update(&%{&1 | delivered?: true})

  # Records a view call that sent the view an event, patch or upload, and
  # passes its result on.
  def delivered(result) do
    record_delivery()
    result
  end

  def record_taken(message), do: update(&%{&1 | taken: [message | &1.taken]})

  defp update(fun) do
    case Process.get(@scope) do
      nil -> :ok
      scope -> Process.put(@scope, fun.(scope))
    end

    :ok
  end
end
