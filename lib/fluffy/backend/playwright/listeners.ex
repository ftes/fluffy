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
end
