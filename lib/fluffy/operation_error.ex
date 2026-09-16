defmodule Fluffy.OperationError do
  @moduledoc """
  An element operation failure with its backend's original cause.

  `backend` is `:phoenix` or `:playwright`; `driver` identifies the active driver.
  `operation` names the public action and `locator` is the query or captured
  file-chooser key. `cause` retains a native Playwright error or a structured
  Phoenix `Fluffy.StrictnessError` or `Fluffy.ActionabilityError`.

  No shared fine-grained failure category is inferred for browser errors.
  Failed assertions remain `ExUnit.AssertionError`. Invalid arguments,
  unsupported capabilities, and unexpected programming errors are not wrapped.
  """

  defexception [:backend, :driver, :operation, :locator, :cause, :message]

  @impl true
  def exception(options) do
    backend = Keyword.fetch!(options, :backend)
    driver = Keyword.fetch!(options, :driver)
    operation = Keyword.fetch!(options, :operation)
    locator = Keyword.fetch!(options, :locator)
    cause = Keyword.fetch!(options, :cause)

    description =
      case locator do
        %Fluffy.Locator{} -> Fluffy.Locator.describe(locator)
        key -> "captured file chooser #{inspect(key)}"
      end

    %__MODULE__{
      backend: backend,
      driver: driver,
      operation: operation,
      locator: locator,
      cause: cause,
      message: "#{backend} #{operation} failed for #{description}\n" <> format(cause)
    }
  end

  defp format(cause) when is_exception(cause), do: Exception.message(cause)
  defp format(cause), do: Fluffy.Playwright.Diagnostics.format(cause)
end
