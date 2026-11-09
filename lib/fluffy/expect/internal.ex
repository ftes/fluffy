defmodule Fluffy.Expect.Internal do
  @moduledoc false
  # Builds, matches and describes `Fluffy.Expect` values, outside the module that
  # `import Fluffy.Expect` brings into tests.

  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.Options
  alias Fluffy.URLMatcher

  @doc "Whether `actual` equals `expected` or matches its regular expression."
  def matches?(%Regex{} = expected, actual) when is_binary(actual), do: Regex.match?(expected, actual)

  def matches?(expected, actual), do: actual == expected

  @doc "Whether a page title matches `expected`, comparing normalized whitespace."
  def title_matches?(expected, actual) when is_binary(actual) do
    actual = normalize_text(actual)

    case expected do
      %Regex{} -> matches?(expected, actual)
      expected when is_binary(expected) -> normalize_text(expected) == actual
    end
  end

  def title_matches?(_expected, _actual), do: false

  @doc "`text` with Playwright's whitespace normalization."
  def normalize_text(text) do
    text
    |> String.replace(["\u200B", "\u00AD"], "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  @doc "An expectation with validated shared options."
  def new(target, kind, expected, options \\ []) when is_atom(kind) and is_list(options) do
    %Expect{
      target: target,
      kind: kind,
      expected: expected,
      options: validate_options!(options)
    }
  end

  @doc "Negates `expectation`."
  def negate(%Expect{} = expectation) do
    %{expectation | negated?: not expectation.negated?}
  end

  @doc "Merges validated shared options into `expectation`."
  def merge_options(%Expect{} = expectation, options) when is_list(options) do
    %{expectation | options: Keyword.merge(expectation.options, validate_options!(options))}
  end

  @doc "Describes `expectation` for failure messages."
  def describe(%Expect{} = expectation) do
    expectation
    |> positive_description()
    |> maybe_negated(expectation.negated?)
  end

  defp validate_options!(options), do: Options.validate_expectation!(options)

  defp positive_description(%Expect{target: {:locator, locator}, kind: kind, expected: expected}) do
    "#{Locator.Internal.describe(locator)} #{locator_matcher_description(kind, expected)}"
  end

  defp positive_description(%Expect{target: :page, kind: :url, expected: expected}) do
    "active page to have URL #{URLMatcher.describe(expected)}"
  end

  defp positive_description(%Expect{target: :page, kind: :title, expected: expected}) do
    "active page to have title #{inspect(expected)}"
  end

  defp positive_description(%Expect{target: :page, kind: :opener, expected: expected}) do
    "active page to have opener #{inspect(expected)}"
  end

  defp locator_matcher_description(:checked, :checked), do: "to be checked"
  defp locator_matcher_description(:checked, :unchecked), do: "to be unchecked"
  defp locator_matcher_description(:checked, :indeterminate), do: "to be indeterminate"
  defp locator_matcher_description(:count, expected), do: "to have count #{inspect(expected)}"
  defp locator_matcher_description(:disabled, _expected), do: "to be disabled"
  defp locator_matcher_description(:editable, _expected), do: "to be editable"
  defp locator_matcher_description(:enabled, _expected), do: "to be enabled"
  defp locator_matcher_description(:focused, _expected), do: "to be focused"
  defp locator_matcher_description(:value, expected), do: "to have value #{inspect(expected)}"
  defp locator_matcher_description(:values, expected), do: "to have values #{inspect(expected)}"
  defp locator_matcher_description(:visible, _expected), do: "to be visible"
  defp locator_matcher_description(:attached, _expected), do: "to be attached"
  defp locator_matcher_description(:hidden, _expected), do: "to be hidden"
  defp locator_matcher_description(:empty, _expected), do: "to be empty"
  defp locator_matcher_description(:class, expected), do: "to have class #{inspect(expected)}"
  defp locator_matcher_description(:contain_class, expected), do: "to contain class #{inspect(expected)}"
  defp locator_matcher_description(:id, expected), do: "to have id #{inspect(expected)}"

  defp locator_matcher_description(:text, {expected, options}),
    do: "to have text #{inspect(expected)}#{ignoring_case(options)}"

  defp locator_matcher_description(:contain_text, {expected, options}),
    do: "to contain text #{inspect(expected)}#{ignoring_case(options)}"

  defp locator_matcher_description(:attribute, {name, nil, _options}), do: "to have attribute #{inspect(name)}"

  defp locator_matcher_description(:attribute, {name, value, options}),
    do: "to have attribute #{inspect(name)} with value #{inspect(value)}#{ignoring_case(options)}"

  defp ignoring_case(options), do: if(options[:ignore_case], do: ", ignoring case", else: "")

  defp maybe_negated(description, false), do: description
  defp maybe_negated(description, true), do: "not " <> description
end
