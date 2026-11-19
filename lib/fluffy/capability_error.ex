defmodule Fluffy.CapabilityError do
  @moduledoc """
  Raised when a driver cannot support a requested action or assertion.

  `capability` is the feature's id in `Fluffy.Capability.matrix/0`, and `operation` the
  call that needs it, or `nil` when the feature is in the page rather than the call.
  """

  defexception [:capability, :operation, :driver, :detail, :message]

  @impl true
  def exception(options) do
    capability = Keyword.fetch!(options, :capability)
    driver = Keyword.fetch!(options, :driver)
    detail = Keyword.fetch!(options, :detail)

    %__MODULE__{
      capability: capability,
      operation: Keyword.get(options, :operation),
      driver: driver,
      detail: detail,
      message:
        "#{inspect(driver)} does not support #{inspect(capability)}: #{detail}. " <>
          "Use a Playwright session for this operation."
    }
  end
end
