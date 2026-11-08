defmodule Fluffy.Driver.Live.Delivery do
  @moduledoc false

  # Whether one of the running Live action's events reached the view. The
  # driver's `act` tracks it around the action, and each view call that
  # delivers an event records it, so an action whose later call finds the view
  # gone still counts the events that reached it before. Outside an action,
  # nothing tracks delivery, so recording does nothing.

  @delivered {__MODULE__, :delivered}

  def track(action) when is_function(action, 0) do
    Process.put(@delivered, false)

    try do
      result = action.()
      {result, Process.get(@delivered)}
    after
      Process.delete(@delivered)
    end
  end

  def record do
    if Process.get(@delivered) == false, do: Process.put(@delivered, true)
    :ok
  end

  # Records a view call that sent the view an event, patch or upload, and
  # passes its result on.
  def delivered(result) do
    record()
    result
  end
end
