defmodule Fluffy.Backend.Playwright.Listeners do
  @moduledoc false

  # Native listeners as `{module, target, event, listener}`, such as
  # `{PlaywrightEx.Page, page, :close, fun}`.

  @doc "Registers listeners; a failed registration releases those registered before it."
  def register(listeners) do
    Enum.reduce(listeners, [], fn {module, target, event, listener} = entry, registered ->
      try do
        module.on(target, event, listener)
      catch
        kind, reason ->
          release(registered)
          :erlang.raise(kind, reason, __STACKTRACE__)
      end

      [entry | registered]
    end)
  end

  @doc "Removes listeners."
  def release(listeners) do
    for {module, target, event, listener} <- listeners do
      try do
        module.off(target, event, listener)
      catch
        # A lost driver already released its listeners. Cleanup must
        # preserve the event outcome or the caller's original failure.
        _kind, _reason -> :ok
      end
    end

    :ok
  end

  @doc """
  Runs `fun` with the listeners `listen` builds for a fresh ref, which tags the
  messages they send the caller; afterwards they are removed and their pending
  messages dropped.
  """
  def listening(listen, fun) do
    ref = make_ref()
    listeners = register(listen.(ref))

    try do
      fun.(ref)
    after
      release(listeners)
      flush(ref)
    end
  end

  defp flush(ref) do
    receive do
      {^ref, _event} -> flush(ref)
      {^ref, _event, _value} -> flush(ref)
    after
      0 -> :ok
    end
  end
end
