defmodule Fluffy.Driver.Phoenix.Validation do
  @moduledoc false

  alias Fluffy.CapabilityError
  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.Session

  @browser_only_kinds [:accessible_error_message, :aria_snapshot, :css, :js_property, :screenshot]

  def validate_operation!(session, operation, arguments) do
    Enum.each(arguments, &validate_argument!(Session.current_driver(session), operation, &1))
    :ok
  end

  defp validate_argument!(driver, operation, %Expect{target: {:locator, locator}} = expectation) do
    validate_argument!(driver, operation, locator)

    if expectation.kind == :focused do
      raise CapabilityError,
        capability: :focus,
        operation: operation,
        driver: driver,
        detail: "focus state requires a browser"
    end

    if expectation.kind == :in_viewport do
      raise CapabilityError,
        capability: :computed_browser_semantics,
        operation: operation,
        driver: driver,
        detail: "viewport intersection requires a browser"
    end

    if expectation.kind in @browser_only_kinds, do: browser_only_expectation!(driver, operation)

    if expectation.kind == :checked and expectation.expected == :indeterminate do
      raise CapabilityError,
        capability: :indeterminate_checked_state,
        operation: operation,
        driver: driver,
        detail: "indeterminate is a browser-owned DOM property"
    end

    if expectation.kind in [:text, :contain_text] and Keyword.has_key?(elem(expectation.expected, 1), :use_inner_text) do
      raise CapabilityError,
        capability: :computed_browser_semantics,
        operation: operation,
        driver: driver,
        detail: "use_inner_text: reads text as the browser renders it"
    end
  end

  defp validate_argument!(driver, operation, %Expect{target: :page, kind: kind})
       when kind in [:screenshot, :aria_snapshot], do: browser_only_expectation!(driver, operation)

  defp validate_argument!(driver, operation, %Locator{} = locator) do
    if Locator.Internal.crosses_frame?(locator) do
      raise CapabilityError,
        capability: :frames,
        operation: operation,
        driver: driver,
        detail: "frame traversal is not supported by Static and LiveView"
    end

    case Locator.Internal.playwright_option(locator) do
      nil ->
        :ok

      {key, _value} ->
        raise CapabilityError,
          capability: :playwright_locator_options,
          operation: operation,
          driver: driver,
          detail: "#{inspect(key)} is a Playwright locator option"
    end
  end

  defp validate_argument!(_driver, _operation, _argument), do: :ok

  defp browser_only_expectation!(driver, operation) do
    raise CapabilityError,
      capability: :computed_browser_semantics,
      operation: operation,
      driver: driver,
      detail: "computed styles, accessibility state, JavaScript properties and screenshots require a browser"
  end
end
