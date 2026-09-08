defmodule Fluffy.Locator.Playwright do
  @moduledoc false

  alias Fluffy.Locator
  alias PlaywrightEx.Selector

  def selector(%Locator{} = locator) do
    locator.operations
    |> Enum.reduce(Selector.none(), &apply_operation/2)
    |> Selector.build()
  end

  defp apply_operation({:css, css}, selector) do
    Selector.concat(selector, Selector.css(css))
  end

  defp apply_operation({:role, role, options}, selector) do
    role_selector =
      case Keyword.get(options, :name) do
        nil ->
          "internal:role=#{role}"

        name ->
          "internal:role=#{role}[name=#{attribute_value(name, Keyword.get(options, :exact, false))}]"
      end

    Selector.concat(selector, role_selector)
  end

  defp apply_operation({:text, text, options}, selector) do
    text_selector = text_selector("internal:text", text, Keyword.get(options, :exact, false))
    Selector.concat(selector, text_selector)
  end

  defp apply_operation({:label, text, options}, selector) do
    label_selector = text_selector("internal:label", text, Keyword.get(options, :exact, false))
    Selector.concat(selector, label_selector)
  end

  defp apply_operation({:attribute, attribute_name, text, options}, selector) do
    attribute_selector =
      internal_attribute_selector(
        "internal:attr",
        attribute_name,
        text,
        Keyword.get(options, :exact, false)
      )

    Selector.concat(selector, attribute_selector)
  end

  defp apply_operation({:test_id, attribute_name, test_id}, selector) do
    Selector.concat(
      selector,
      internal_attribute_selector("internal:testid", attribute_name, test_id, true)
    )
  end

  defp apply_operation({:filter, options}, selector) do
    Enum.reduce(options, selector, fn
      {:has_text, text}, current ->
        has_text = text_selector("internal:has-text", text, false)

        Selector.concat(current, has_text)

      {:has_not_text, text}, current ->
        has_not_text = text_selector("internal:has-not-text", text, false)

        Selector.concat(current, has_not_text)

      {:has, %Locator{} = child}, current ->
        Selector.has(current, selector(child))

      {:has_not, %Locator{} = child}, current ->
        Selector.concat(current, "internal:has-not=#{JSON.encode!(selector(child))}")
    end)
  end

  defp apply_operation({:nth, index}, selector) do
    Selector.concat(selector, Selector.at(index))
  end

  defp internal_attribute_selector(engine, attribute_name, value, exact?) do
    ~s(#{engine}=[#{attribute_name}=#{attribute_value(value, exact?)}])
  end

  defp text_selector(engine, value, exact?) do
    suffix = if exact?, do: "s", else: "i"
    "#{engine}=#{JSON.encode!(value)}#{suffix}"
  end

  defp attribute_value(value, exact?) do
    suffix = if exact?, do: "s", else: "i"
    escaped = value |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")
    ~s("#{escaped}"#{suffix})
  end
end
