defmodule Fluffy.URLMatcher do
  @moduledoc false

  alias Fluffy.Options

  @enforce_keys [:source]
  defstruct [:source, path: :ignore, query: :ignore, query_mode: :exact, fragment: :ignore]

  @type query_values :: [String.t()]
  @type query_multimap :: %{String.t() => query_values()}
  @opaque t :: %__MODULE__{
            source: keyword(),
            path: String.t() | :ignore,
            query: query_multimap() | :ignore,
            query_mode: :exact | :subset,
            fragment: String.t() | nil | :ignore
          }

  @spec new!(keyword()) :: t()
  def new!(components) when is_list(components) do
    validated = Options.validate_url_matcher!(components)
    ensure_component!(validated)
    ensure_query_mode_has_query!(components)

    %__MODULE__{
      source: validated,
      path: Keyword.get(validated, :path, :ignore),
      query: normalize_expected_query(validated),
      query_mode: Keyword.get(validated, :query_mode, :exact),
      fragment: Keyword.get(validated, :fragment, :ignore)
    }
  end

  @spec matches?(String.t() | {:ignore_case, String.t()} | Regex.t() | t() | (URI.t() -> boolean()), String.t()) ::
          boolean()
  def matches?(expected, actual) when is_binary(expected) and is_binary(actual), do: actual == expected

  def matches?({:ignore_case, expected}, actual) when is_binary(actual),
    do: String.downcase(actual) == String.downcase(expected)

  def matches?(%Regex{} = expected, actual) when is_binary(actual), do: Regex.match?(expected, actual)

  def matches?(%__MODULE__{} = matcher, actual) when is_binary(actual) do
    uri = URI.parse(actual)

    component_matches?(matcher.path, uri.path) and
      query_matches?(matcher.query, matcher.query_mode, decode_query(uri.query)) and
      component_matches?(matcher.fragment, uri.fragment)
  end

  def matches?(predicate, actual) when is_function(predicate, 1) and is_binary(actual) do
    !!predicate.(URI.parse(actual))
  end

  def matches?(_expected, _actual), do: false

  @spec describe(String.t() | {:ignore_case, String.t()} | Regex.t() | t() | (URI.t() -> boolean())) :: String.t()
  def describe(%__MODULE__{source: source}), do: inspect(source)
  def describe({:ignore_case, expected}), do: "#{inspect(expected)}, ignoring case"
  def describe(expected), do: inspect(expected)

  @doc """
  Applies `ignore_case:` to a string or regular expression. It takes precedence over a
  regular expression's own `i` flag, as in PlaywrightEx.
  """
  def ignore_case(expected, nil), do: expected

  # A leading inline flag overrides the regex's own `i` option.
  def ignore_case(%Regex{} = expected, ignore_case) do
    flag = if ignore_case, do: "(?i)", else: "(?-i)"
    Regex.compile!(flag <> Regex.source(expected), Regex.opts(expected))
  end

  def ignore_case(expected, false), do: expected
  def ignore_case(expected, true) when is_binary(expected), do: {:ignore_case, expected}

  def ignore_case(_expected, true), do: raise(ArgumentError, "ignore_case: requires a string or regular expression URL")

  defp ensure_component!(components) do
    if Enum.any?([:path, :query, :fragment], &Keyword.has_key?(components, &1)) do
      :ok
    else
      raise NimbleOptions.ValidationError,
        message: "expected at least one of :path, :query, or :fragment",
        key: nil,
        value: components
    end
  end

  defp ensure_query_mode_has_query!(components) do
    if Keyword.has_key?(components, :query_mode) and not Keyword.has_key?(components, :query) do
      raise NimbleOptions.ValidationError,
        message: ":query_mode requires a :query component",
        key: :query_mode,
        value: Keyword.fetch!(components, :query_mode)
    end
  end

  defp normalize_expected_query(components) do
    case Keyword.fetch(components, :query) do
      {:ok, query} -> Map.new(query, fn {name, values} -> {name, List.wrap(values)} end)
      :error -> :ignore
    end
  end

  defp decode_query(nil), do: %{}

  defp decode_query(query) do
    query
    |> URI.query_decoder()
    |> Enum.reduce(%{}, fn {name, value}, result ->
      Map.update(result, name, [value], &[value | &1])
    end)
    |> Map.new(fn {name, reversed_values} -> {name, Enum.reverse(reversed_values)} end)
  end

  defp component_matches?(:ignore, _actual), do: true
  defp component_matches?(expected, actual), do: expected == actual

  defp query_matches?(:ignore, _mode, _actual), do: true
  defp query_matches?(expected, :exact, actual), do: expected == actual

  defp query_matches?(expected, :subset, actual) do
    Enum.all?(expected, fn {name, values} -> Map.get(actual, name, :missing) == values end)
  end
end
