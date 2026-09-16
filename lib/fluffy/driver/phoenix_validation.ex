defmodule Fluffy.Driver.PhoenixValidation do
  @moduledoc false

  alias Fluffy.CapabilityError
  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.Session

  def validate_operation!(session, _operation, arguments) do
    Enum.each(arguments, &validate_argument!(Session.current_driver(session), &1))
    :ok
  end

  defp validate_argument!(driver, %Expect{target: {:locator, locator}} = expectation) do
    validate_argument!(driver, locator)

    if expectation.kind == :checked and expectation.expected == :indeterminate do
      raise CapabilityError,
        capability: :indeterminate_checked_state,
        driver: driver,
        detail: "indeterminate is a browser-owned DOM property"
    end
  end

  defp validate_argument!(driver, %Locator{} = locator) do
    if Locator.crosses_frame?(locator) do
      raise CapabilityError,
        capability: :frames,
        driver: driver,
        detail: "frame traversal is not supported by Static and LiveView"
    end
  end

  defp validate_argument!(_driver, _argument), do: :ok
end
