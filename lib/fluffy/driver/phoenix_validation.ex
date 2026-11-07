defmodule Fluffy.Driver.PhoenixValidation do
  @moduledoc false

  alias Fluffy.CapabilityError
  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.Session

  @playwright_locator_keys Fluffy.Options.playwright_locator_keys()

  def validate_operation!(session, _operation, arguments) do
    Enum.each(arguments, &validate_argument!(Session.current_driver(session), &1))
    :ok
  end

  defp validate_argument!(driver, %Expect{target: {:locator, locator}} = expectation) do
    validate_argument!(driver, locator)

    if expectation.kind == :focused do
      raise CapabilityError,
        capability: :focus,
        driver: driver,
        detail: "focus state requires a browser"
    end

    if expectation.kind == :checked and expectation.expected == :indeterminate do
      raise CapabilityError,
        capability: :indeterminate_checked_state,
        driver: driver,
        detail: "indeterminate is a browser-owned DOM property"
    end
  end

  defp validate_argument!(driver, %Locator{} = locator) do
    if Locator.Internal.crosses_frame?(locator) do
      raise CapabilityError,
        capability: :frames,
        driver: driver,
        detail: "frame traversal is not supported by Static and LiveView"
    end

    case Locator.Internal.playwright_option(locator) do
      nil ->
        :ok

      {key, %Regex{}} when key not in @playwright_locator_keys ->
        raise CapabilityError,
          capability: :playwright_locator_options,
          driver: driver,
          detail: "a regular expression #{inspect(key)} is a Playwright locator option"

      {key, _value} ->
        raise CapabilityError,
          capability: :playwright_locator_options,
          driver: driver,
          detail: "#{inspect(key)} is a Playwright locator option"
    end
  end

  defp validate_argument!(driver, [{key, _value} | _] = options) when is_atom(key) do
    if key =
         Keyword.keyword?(options) && Enum.find(Keyword.keys(options), &(&1 in Fluffy.Options.playwright_option_keys())) do
      raise CapabilityError,
        capability: :playwright_action_options,
        driver: driver,
        detail: "#{inspect(key)} is a Playwright option"
    end
  end

  defp validate_argument!(_driver, _argument), do: :ok
end
