defmodule Fluffy.ClientDOM.Expectation do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.Expect
  alias Fluffy.HTML.Aria
  alias Fluffy.HTML.Semantics
  alias Fluffy.Locator.Static
  # StringUtils is internal to PlaywrightEx, which is pinned.
  alias PlaywrightEx.Isomorphic.StringUtils

  # Evaluate one DOM snapshot. Drivers own retries, negation, and diagnostics.
  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :count, expected: expected}) do
    actual = client_dom |> ClientDOM.resolve(locator) |> length()
    {actual == expected, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :visible}) do
    actual = count_visible(client_dom, strict_candidates!(client_dom, locator))
    {actual > 0, actual}
  end

  # An empty locator passes `to_be_hidden` and, negated, still fails, as in Playwright.
  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :hidden}) do
    actual = count_visible(client_dom, strict_candidates!(client_dom, locator))
    {actual == 0, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :attached}) do
    actual = client_dom |> strict_candidates!(locator) |> length()
    {actual > 0, actual}
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :empty} = expectation) do
    with_element(client_dom, locator, expectation, fn
      %{tag: tag} when tag in ["input", "textarea"] ->
        actual = ClientDOM.value(client_dom, locator)
        {actual == "", actual}

      target ->
        actual = Semantics.text(target)
        {String.trim(actual) == "", actual}
    end)
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :text, expected: {expected, options}} = expectation) do
    match = &text_matches?(&1, &2, normalize: true, ignore_case: options[:ignore_case])
    evaluate_text(client_dom, locator, expectation, expected, match, true)
  end

  def evaluate(
        client_dom,
        %Expect{target: {:locator, locator}, kind: :contain_text, expected: {expected, options}} = expectation
      ) do
    match = &text_matches?(&1, &2, normalize: true, ignore_case: options[:ignore_case], contains: true)
    evaluate_text(client_dom, locator, expectation, expected, match, false)
  end

  def evaluate(
        client_dom,
        %Expect{target: {:locator, locator}, kind: :attribute, expected: {name, value, options}} = expectation
      ) do
    with_element(client_dom, locator, expectation, fn target ->
      actual = Semantics.attribute(target.attributes, name)

      cond do
        is_nil(value) -> {not is_nil(actual), actual}
        is_nil(actual) -> {false, actual}
        true -> {text_matches?(value, actual, ignore_case: options[:ignore_case]), actual}
      end
    end)
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :class, expected: expected} = expectation) do
    evaluate_class(client_dom, locator, expectation, expected, &text_matches?(&1, &2, []))
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :contain_class, expected: expected} = expectation) do
    evaluate_class(client_dom, locator, expectation, expected, &contains_classes?/2)
  end

  def evaluate(client_dom, %Expect{target: {:locator, locator}, kind: :id, expected: expected} = expectation) do
    with_element(client_dom, locator, expectation, fn target ->
      actual = Semantics.attribute(target.attributes, "id") || ""
      {text_matches?(expected, actual, []), actual}
    end)
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

  defp evaluate_text(client_dom, locator, _expectation, expected, match, exact_length?) when is_list(expected) do
    actual = client_dom |> ClientDOM.targets(locator) |> Enum.map(&Semantics.text/1)
    {matches_in_order?(expected, actual, match, exact_length?), actual}
  end

  defp evaluate_text(client_dom, locator, expectation, expected, match, _exact_length?) do
    with_element(client_dom, locator, expectation, fn target ->
      actual = Semantics.text(target)
      {match.(expected, actual), actual}
    end)
  end

  defp evaluate_class(client_dom, locator, _expectation, expected, match) when is_list(expected) do
    actual = client_dom |> ClientDOM.targets(locator) |> Enum.map(&class_attribute/1)
    {matches_in_order?(expected, actual, match, true), actual}
  end

  defp evaluate_class(client_dom, locator, expectation, expected, match) do
    with_element(client_dom, locator, expectation, fn target ->
      actual = class_attribute(target)
      {match.(expected, actual), actual}
    end)
  end

  # Without an element, neither the assertion nor its negation can pass.
  defp with_element(client_dom, locator, %Expect{negated?: negated?}, fun) do
    case ClientDOM.targets(client_dom, locator) do
      [] -> {negated?, :not_found}
      [target] -> fun.(target)
      targets -> strictness_error!(locator, Enum.map(targets, & &1.element))
    end
  end

  defp count_visible(_client_dom, []), do: 0

  defp count_visible(client_dom, candidates) do
    aria = Aria.for_document(client_dom.document)
    Enum.count(candidates, &Static.structurally_visible?(aria, &1))
  end

  defp strict_candidates!(client_dom, locator) do
    candidates = ClientDOM.resolve(client_dom, locator)
    if length(candidates) > 1, do: strictness_error!(locator, candidates)
    candidates
  end

  defp strictness_error!(locator, candidates) do
    raise ExUnit.AssertionError, message: Fluffy.Expectation.strictness_message(locator, candidates)
  end

  # Each expected value must match a later element than the one before it. An
  # exact length makes that a pairwise comparison.
  defp matches_in_order?(expected, actual, match, exact_length?) do
    (not exact_length? or length(expected) == length(actual)) and matches_sequentially?(expected, actual, match)
  end

  defp matches_sequentially?([], _actual, _match), do: true
  defp matches_sequentially?(_expected, [], _match), do: false

  defp matches_sequentially?([expected | rest] = values, [actual | remaining], match) do
    if match.(expected, actual) do
      matches_sequentially?(rest, remaining, match)
    else
      matches_sequentially?(values, remaining, match)
    end
  end

  defp text_matches?(%Regex{} = expected, actual, options) do
    expected |> Expect.Internal.ignore_case(options[:ignore_case]) |> Regex.match?(actual)
  end

  defp text_matches?(expected, actual, options) when is_binary(expected) do
    expected = comparable(expected, options)
    actual = comparable(actual, options)
    if options[:contains], do: String.contains?(actual, expected), else: actual == expected
  end

  defp comparable(text, options) do
    text = if options[:normalize], do: StringUtils.normalize_white_space(text), else: text
    if options[:ignore_case], do: String.downcase(text), else: text
  end

  defp contains_classes?(expected, actual) do
    classes = String.split(actual)
    expected |> String.split() |> Enum.all?(&(&1 in classes))
  end

  defp class_attribute(target), do: Semantics.attribute(target.attributes, "class") || ""
end
