defmodule Fluffy.Backend.Playwright.Listeners do
  @moduledoc false

  # Native listeners as `{module, target, event, listener}`, such as
  # `{PlaywrightEx.Page, page, :close, fun}`.

  @doc "Registers listeners and returns them."
  def register(listeners) do
    for {module, target, event, listener} <- listeners, do: module.on(target, event, listener)
    listeners
  end

  @doc "Removes listeners; as in Playwright, this never fails, even once the driver is lost."
  def release(listeners) do
    for {module, target, event, listener} <- listeners, do: module.off(target, event, listener)
    :ok
  end

  @doc """
  Runs `fun` with the listeners `listen` builds for a fresh ref, a process alias
  they send their messages to, tagged with it; afterwards they are removed and
  their pending messages dropped.

  Removing a listener does not wait for a call of it already running, which can
  still send. Deactivating the alias drops those sends.
  """
  def listening(listen, fun) do
    ref = Process.alias()

    try do
      listeners = register(listen.(ref))

      try do
        fun.(ref)
      after
        release(listeners)
      end
    after
      Process.unalias(ref)
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
