defmodule Fluffy.Internal.OperationFailure do
  @moduledoc false

  alias Fluffy.ActionabilityError
  alias Fluffy.Backend.Phoenix
  alias Fluffy.Internal.NavigationFailure
  alias Fluffy.LiveViewError
  alias Fluffy.Session
  alias Fluffy.StrictnessError

  # Turns an error a driver operation raised into what the user sees, once, for both
  # backends. Phoenix drivers raise structured causes, which element actions, taking their
  # locator first, wrap; navigation failures come from both backends.
  def normalize(%Session{} = session, operation, arguments, %NavigationFailure{} = failure),
    do: navigation(session, public_operation(operation, arguments), failure)

  def normalize(%Session{} = session, operation, arguments, cause)
      when is_struct(cause, StrictnessError) or is_struct(cause, ActionabilityError) or is_struct(cause, LiveViewError) do
    if Session.backend(session) == Phoenix,
      do: wrap_operation(session, operation, arguments, cause),
      else: cause
  end

  def normalize(_session, _operation, _arguments, cause), do: cause

  @doc """
  The `Fluffy.OperationError` of a failed navigation, with Playwright's error or Fluffy's
  account of the failure as its cause.
  """
  def navigation(%Session{} = session, operation, error) do
    {backend, driver} = backend_driver(session)

    Fluffy.OperationError.exception(
      backend: backend,
      driver: driver,
      operation: operation,
      locator: nil,
      cause: navigation_cause(error)
    )
  end

  defp navigation_cause(%NavigationFailure{message: message}), do: message
  defp navigation_cause(error), do: error

  # As Playwright's expectation shows an injected script error.
  defp wrap_operation(_session, :expect, [%Fluffy.Expect{} = expectation], %ActionabilityError{} = cause) do
    ExUnit.AssertionError.exception(
      message: "Expected #{Fluffy.Expect.Internal.describe(expectation)}\nError: #{Exception.message(cause)}"
    )
  end

  defp wrap_operation(_session, :expect, _arguments, cause) when not is_struct(cause, LiveViewError) do
    ExUnit.AssertionError.exception(message: Exception.message(cause))
  end

  defp wrap_operation(session, operation, [%Fluffy.Locator{} = locator | _rest] = arguments, cause),
    do: phoenix_operation(session, public_operation(operation, arguments), locator, cause)

  # A view that failed under an unwrap callback; the callback's own errors stay as raised.
  defp wrap_operation(session, operation, _arguments, %LiveViewError{} = cause),
    do: phoenix_operation(session, operation, nil, cause)

  defp wrap_operation(_session, _operation, _arguments, cause), do: cause

  defp phoenix_operation(session, operation, locator, cause) do
    Fluffy.OperationError.exception(
      backend: :phoenix,
      driver: Session.current_driver(session),
      operation: operation,
      locator: locator,
      cause: cause
    )
  end

  defp public_operation(:set_checked, [_locator, true | _]), do: :check
  defp public_operation(:set_checked, [_locator, false | _]), do: :uncheck
  defp public_operation(operation, _arguments), do: operation

  # A Playwright page's driver is always `:playwright`, also once the page has closed.
  defp backend_driver(session) do
    case Session.backend(session) do
      Fluffy.Backend.Playwright -> {:playwright, :playwright}
      Phoenix -> {:phoenix, Session.current_driver(session)}
    end
  end

  def raise_playwright!(operation, locator, cause), do: raise(playwright(operation, locator, cause))

  def playwright(operation, locator, cause) do
    Fluffy.OperationError.exception(
      backend: :playwright,
      driver: :playwright,
      operation: operation,
      locator: locator,
      cause: cause
    )
  end
end
