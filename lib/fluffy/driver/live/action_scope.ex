defmodule Fluffy.Driver.Live.ActionScope do
  @moduledoc false

  # What the running Live action did to its view. The driver's `act` runs each
  # action in a scope, which records whether one of its events reached the
  # view, so an action whose later call finds the view gone still counts the
  # events that reached it before. Outside an action, recording does nothing.
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
  #   * A view message saying how the view left (a redirect, the view's exit)
  #     stays unread: the driver's `leave_unread/1` puts it back as it is read,
  #     so a call that fails before following it leaves it for the next call.
  #   * A retry on another page runs after the action's scope ended, as an
  #     action of its own, so it does not count the first page's deliveries.
  #     It passes the redirects followed so far through `after_redirects/2`,
  #     so the redirect limit holds across retries.

  @scope {__MODULE__, :scope}
  @redirects {__MODULE__, :redirects}

  def run(action) when is_function(action, 0) do
    previous = Process.put(@scope, false)

    try do
      action.()
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

  defp restore(key, nil), do: Process.delete(key)
  defp restore(key, previous), do: Process.put(key, previous)

  def delivered?, do: Process.get(@scope, false)

  def record_delivery do
    if Process.get(@scope) == false, do: Process.put(@scope, true)
    :ok
  end

  # Records a view call that sent the view an event, patch or upload, and
  # passes its result on.
  def delivered(result) do
    record_delivery()
    result
  end
end
