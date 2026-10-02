defmodule Fluffy.ClientDOM.Expectation do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.Expect
  alias Fluffy.Locator.Static

  # Evaluate one DOM snapshot. Drivers own retries, negation, and diagnostics.
  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :count, expected: expected}) do
    actual = client_dom |> ClientDOM.resolve(locator) |> length()
    {actual == expected, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :visible}) do
    candidates = ClientDOM.resolve(client_dom, locator)

    if length(candidates) > 1 do
      raise ExUnit.AssertionError, message: Fluffy.Expectation.strictness_message(locator, candidates)
    end

    actual = Enum.count(candidates, &Static.structurally_visible?/1)
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
end
