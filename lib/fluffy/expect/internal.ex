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
    actual = normalize_title(actual)

    case expected do
      %Regex{} -> matches?(expected, actual)
      expected when is_binary(expected) -> normalize_title(expected) == actual
    end
  end

  def title_matches?(_expected, _actual), do: false

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

  defp maybe_negated(description, false), do: description
  defp maybe_negated(description, true), do: "not " <> description

  defp normalize_title(title) do
    title
    |> String.replace(["\u200B", "\u00AD"], "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
