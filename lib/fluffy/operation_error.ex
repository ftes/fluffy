defmodule Fluffy.OperationError do
  @moduledoc """
  An operation failure with its backend's original cause.

  `backend` is `:phoenix` or `:playwright`; `driver` is the page's driver when the operation
  failed, so `:unvisited` if a Phoenix session's first `visit` failed before any page loaded.
  `operation` names the public call and `locator` is the query,
  `Fluffy.FileChooser` handle, or `nil` for an operation on the page as a whole, such
  as a failed navigation. `cause` retains a native Playwright error, a structured Phoenix
  `Fluffy.StrictnessError`, `Fluffy.ActionabilityError` or `Fluffy.LiveViewError`, or,
  for a navigation that Fluffy found failed, a message saying why: an aborted response,
  too many redirects, a LiveView that rejected its connection or did not connect, or a page
  that did not respond to Fluffy's document check.

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
        %Fluffy.Locator{} -> Fluffy.Locator.Internal.describe(locator)
        %Fluffy.FileChooser{} -> "file chooser"
        nil -> "the page"
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
  defp format(cause) when is_binary(cause), do: cause
  defp format(cause), do: inspect(cause, pretty: true, limit: :infinity, printable_limit: :infinity)
end
