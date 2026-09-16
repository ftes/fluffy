defmodule Fluffy.Internal.OperationFailure do
  @moduledoc false

  # Element actions take their locator as the first driver argument. Assertions
  # take an Expect and unwrap takes a callback, so neither enters this envelope.
  def normalize(%Fluffy.Session{backend: Fluffy.Backend.Phoenix} = session, operation, arguments, cause)
      when is_struct(cause, Fluffy.StrictnessError) or is_struct(cause, Fluffy.ActionabilityError) do
    wrap_operation(session, operation, arguments, cause)
  end

  def normalize(_session, _operation, _arguments, cause), do: cause

  defp wrap_operation(_session, :expect, _arguments, cause) do
    ExUnit.AssertionError.exception(message: Exception.message(cause))
  end

  defp wrap_operation(session, operation, [%Fluffy.Locator{} = locator | rest], cause) do
    Fluffy.OperationError.exception(
      backend: :phoenix,
      driver: Fluffy.Session.current_driver(session),
      operation: public_operation(operation, rest),
      locator: locator,
      cause: cause
    )
  end

  defp wrap_operation(_session, _operation, _arguments, cause), do: cause

  defp public_operation(:set_checked, [true | _]), do: :check
  defp public_operation(:set_checked, [false | _]), do: :uncheck
  defp public_operation(operation, _arguments), do: operation

  def raise_playwright!(operation, locator, cause) do
    raise Fluffy.OperationError,
      backend: :playwright,
      driver: :playwright,
      operation: operation,
      locator: locator,
      cause: cause
  end
end
