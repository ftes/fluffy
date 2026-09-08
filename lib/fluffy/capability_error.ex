defmodule Fluffy.CapabilityError do
  @moduledoc """
  Raised when a driver cannot truthfully determine a requested browser fact.
  """

  defexception [:capability, :driver, :detail, :message]

  @impl true
  def exception(options) do
    capability = Keyword.fetch!(options, :capability)
    driver = Keyword.fetch!(options, :driver)
    detail = Keyword.fetch!(options, :detail)

    %__MODULE__{
      capability: capability,
      driver: driver,
      detail: detail,
      message:
        "#{inspect(driver)} does not support #{inspect(capability)}: #{detail}. " <>
          "Run this assertion with the Playwright driver."
    }
  end
end
