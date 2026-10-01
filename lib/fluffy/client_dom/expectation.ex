defmodule Fluffy.ClientDOM.Expectation do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.Expect
  alias Fluffy.HTML.Semantics

  # Evaluate one DOM snapshot. Drivers own retries, negation, and diagnostics.
  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :count, expected: expected}) do
    actual = client_dom |> ClientDOM.resolve(locator) |> length()
    {actual == expected, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :visible}) do
    actual = client_dom |> ClientDOM.resolve(locator) |> Enum.count(&structurally_visible?/1)
    {actual > 0, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :disabled}) do
    actual = ClientDOM.disabled?(client_dom, locator)
    {actual, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :editable}) do
    actual = ClientDOM.editable?(client_dom, locator)
    {actual, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :enabled}) do
    actual = not ClientDOM.disabled?(client_dom, locator)
    {actual, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :focused}) do
    actual = ClientDOM.focused?(client_dom, locator)
    {actual, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :checked, expected: expected}) do
    actual = ClientDOM.checked?(client_dom, locator)
    {actual == (expected == :checked), actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :value, expected: expected}) do
    actual = ClientDOM.value(client_dom, locator)
    {actual == expected, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :values, expected: expected}) do
    actual = ClientDOM.selected_values(client_dom, locator)
    {actual == expected, actual}
  end

  defp structurally_visible?(element) do
    attributes =
      case LazyHTML.attributes(element) do
        [attributes] -> attributes
        _other -> []
      end

    not Semantics.has_attribute?(attributes, "hidden") and
      String.downcase(Semantics.attribute(attributes, "aria-hidden") || "false") != "true"
  end
end
