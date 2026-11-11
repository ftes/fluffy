defmodule Fluffy.Locator.Playwright do
  @moduledoc false

  alias Fluffy.Locator
  alias Fluffy.Locator.Internal
  alias PlaywrightEx.Isomorphic.LocatorUtils
  alias PlaywrightEx.Isomorphic.StringUtils

  def selector(%Locator{} = locator) do
    case Enum.reduce(locator.operations, :none, &apply_operation/2) do
      :none -> "*"
      selector -> selector
    end
  end

  def locator(frame, %Locator{} = locator), do: PlaywrightEx.Frame.locator(frame, selector(locator))

  defp apply_operation(:enter_frame, selector), do: concat(selector, "internal:control=enter-frame")

  defp apply_operation({:css, css}, selector) do
    concat(selector, "css=#{css}")
  end

  # Upstream builds role selectors with its options in a fixed order, including
  # Playwright-only states such as `[pressed=true]`.
  defp apply_operation({:role, role, options}, selector) do
    options =
      Map.new(options, fn
        {:include_hidden, include_hidden} -> {:includeHidden, include_hidden}
        option -> option
      end)

    concat(selector, LocatorUtils.get_by_role_selector(role, options))
  end

  # Their options, only `exact:`, are upstream's.
  defp apply_operation({:text, text, options}, selector),
    do: concat(selector, LocatorUtils.get_by_text_selector(text, Map.new(options)))

  defp apply_operation({:label, text, options}, selector),
    do: concat(selector, LocatorUtils.get_by_label_selector(text, Map.new(options)))

  defp apply_operation({:attribute, "placeholder", text, options}, selector),
    do: concat(selector, LocatorUtils.get_by_placeholder_selector(text, Map.new(options)))

  defp apply_operation({:attribute, "alt", text, options}, selector),
    do: concat(selector, LocatorUtils.get_by_alt_text_selector(text, Map.new(options)))

  defp apply_operation({:attribute, "title", text, options}, selector),
    do: concat(selector, LocatorUtils.get_by_title_selector(text, Map.new(options)))

  defp apply_operation({:test_id, attribute_name, test_id}, selector),
    do: concat(selector, LocatorUtils.get_by_test_id_selector(attribute_name, test_id))

  defp apply_operation({:and, right}, selector) do
    concat(selector, "internal:and=#{JSON.encode!(selector(right))}")
  end

  defp apply_operation({:or, right}, selector) do
    concat(selector, "internal:or=#{JSON.encode!(selector(right))}")
  end

  # A chained selector cannot enter a frame; only a parent starting the selector is not chained.
  defp apply_operation({:within, parent, child}, selector) do
    if Internal.crosses_frame?(child) or (selector != :none and Internal.crosses_frame?(parent)) do
      raise ArgumentError,
            "within/2 cannot enter a frame inside a chained locator, got: " <>
              "within(#{Internal.describe(child)}, #{Internal.describe(parent)}); " <>
              "start the locator from the frame instead"
    end

    selector |> chain(selector(parent)) |> chain(selector(child))
  end

  defp apply_operation({:filter, options}, selector) do
    Enum.reduce(options, selector, fn
      {:has_text, text}, current ->
        has_text = text_selector("internal:has-text", text, Keyword.get(options, :exact, false))

        concat(current, has_text)

      {:has_not_text, text}, current ->
        has_not_text = text_selector("internal:has-not-text", text, Keyword.get(options, :exact, false))

        concat(current, has_not_text)

      {:has, %Locator{} = child}, current ->
        concat(current, "internal:has=#{JSON.encode!(selector(child))}")

      {:has_not, %Locator{} = child}, current ->
        concat(current, "internal:has-not=#{JSON.encode!(selector(child))}")

      {:visible, visible?}, current ->
        concat(current, "visible=#{visible?}")

      {:exact, _exact?}, current ->
        current
    end)
  end

  defp apply_operation({:nth, index}, selector) do
    concat(selector, "nth=#{index}")
  end

  # Nesting makes the operands of `and_/2` and `or_/2` in `nested` resolve from each match
  # of `selector`. Playwright rejects a chain with nothing before it.
  defp chain(:none, nested), do: nested
  defp chain(selector, nested), do: concat(selector, "internal:chain=#{JSON.encode!(nested)}")

  defp concat(:none, right), do: right
  defp concat(left, right), do: "#{left} >> #{right}"

  # A regular expression ignores `exact?`, as upstream.
  defp text_selector(engine, value, exact?), do: "#{engine}=#{StringUtils.escape_for_text_selector(value, exact?)}"
end
