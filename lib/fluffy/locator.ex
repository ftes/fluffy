defmodule Fluffy.Locator do
  @moduledoc """
  A lazy, driver-independent element query.

  Role locators accept these options:

  #{NimbleOptions.docs(Fluffy.Options.role_locator_schema())}

  Text, label, placeholder, alternative-text, and title locators accept:

  #{NimbleOptions.docs(Fluffy.Options.exact_locator_schema())}

  Test-id locators accept:

  #{NimbleOptions.docs(Fluffy.Options.test_id_locator_schema())}

  `filter/2` accepts:

  #{NimbleOptions.docs(Fluffy.Options.filter_locator_schema())}
  """

  alias Fluffy.Options

  @enforce_keys [:operations]
  defstruct operations: []

  @type t :: %__MODULE__{operations: [term()]}
  @type role_option :: unquote(NimbleOptions.option_typespec(Options.role_locator_schema()))
  @type exact_option :: unquote(NimbleOptions.option_typespec(Options.exact_locator_schema()))
  @type test_id_option :: unquote(NimbleOptions.option_typespec(Options.test_id_locator_schema()))
  @type filter_option :: unquote(NimbleOptions.option_typespec(Options.filter_locator_schema()))

  def new(operation), do: %__MODULE__{operations: [operation]}

  def append(%__MODULE__{} = locator, operation) do
    update_in(locator.operations, &(&1 ++ [operation]))
  end

  @spec by_role(atom(), [role_option()]) :: t()
  @spec by_role(t(), atom()) :: t()
  @spec by_role(t(), atom(), [role_option()]) :: t()
  def by_role(role, options \\ [])

  def by_role(role, options) when is_atom(role) and is_list(options) do
    new({:role, role, Options.validate_role_locator!(options)})
  end

  def by_role(%__MODULE__{} = parent, role) when is_atom(role) do
    by_role(parent, role, [])
  end

  def by_role(%__MODULE__{} = parent, role, options) when is_atom(role) and is_list(options) do
    append(parent, {:role, role, Options.validate_role_locator!(options)})
  end

  @spec by_text(String.t(), [exact_option()]) :: t()
  @spec by_text(t(), String.t(), [exact_option()]) :: t()
  def by_text(text, options \\ [])

  def by_text(text, options) when is_binary(text) and is_list(options) do
    new({:text, text, Options.validate_exact_locator!(options)})
  end

  def by_text(%__MODULE__{} = parent, text, options) when is_binary(text) and is_list(options) do
    append(parent, {:text, text, Options.validate_exact_locator!(options)})
  end

  @spec by_label(String.t(), [exact_option()]) :: t()
  @spec by_label(t(), String.t(), [exact_option()]) :: t()
  def by_label(text, options \\ [])

  def by_label(text, options) when is_binary(text) and is_list(options) do
    attribute_or_label_locator(:label, text, options)
  end

  def by_label(%__MODULE__{} = parent, text, options) when is_binary(text) and is_list(options) do
    append(parent, {:label, text, Options.validate_exact_locator!(options)})
  end

  @spec by_placeholder(String.t(), [exact_option()]) :: t()
  @spec by_placeholder(t(), String.t(), [exact_option()]) :: t()
  def by_placeholder(text, options \\ [])

  def by_placeholder(text, options) when is_binary(text) and is_list(options) do
    attribute_locator("placeholder", text, options)
  end

  def by_placeholder(%__MODULE__{} = parent, text, options) when is_binary(text) and is_list(options) do
    append_attribute_locator(parent, "placeholder", text, options)
  end

  @spec by_alt_text(String.t(), [exact_option()]) :: t()
  @spec by_alt_text(t(), String.t(), [exact_option()]) :: t()
  def by_alt_text(text, options \\ [])

  def by_alt_text(text, options) when is_binary(text) and is_list(options) do
    attribute_locator("alt", text, options)
  end

  def by_alt_text(%__MODULE__{} = parent, text, options) when is_binary(text) and is_list(options) do
    append_attribute_locator(parent, "alt", text, options)
  end

  @spec by_title(String.t(), [exact_option()]) :: t()
  @spec by_title(t(), String.t(), [exact_option()]) :: t()
  def by_title(text, options \\ [])

  def by_title(text, options) when is_binary(text) and is_list(options) do
    attribute_locator("title", text, options)
  end

  def by_title(%__MODULE__{} = parent, text, options) when is_binary(text) and is_list(options) do
    append_attribute_locator(parent, "title", text, options)
  end

  @spec by_test_id(String.t(), [test_id_option()]) :: t()
  @spec by_test_id(t(), String.t(), [test_id_option()]) :: t()
  def by_test_id(test_id, options \\ [])

  def by_test_id(test_id, options) when is_binary(test_id) and is_list(options) do
    options = Options.validate_test_id_locator!(options)
    new({:test_id, validate_attribute!(options[:attribute]), test_id})
  end

  def by_test_id(%__MODULE__{} = parent, test_id, options) when is_binary(test_id) and is_list(options) do
    options = Options.validate_test_id_locator!(options)
    append(parent, {:test_id, validate_attribute!(options[:attribute]), test_id})
  end

  def by_css(css) when is_binary(css), do: new({:css, css})

  def by_css(%__MODULE__{} = parent, css) when is_binary(css) do
    append(parent, {:css, css})
  end

  @spec filter(t(), [filter_option()]) :: t()
  def filter(%__MODULE__{} = locator, options) when is_list(options) do
    append(
      locator,
      {:filter, Options.validate_filter_locator!(options)}
    )
  end

  def first(%__MODULE__{} = locator), do: append(locator, {:nth, 0})
  def last(%__MODULE__{} = locator), do: append(locator, {:nth, -1})

  def nth(%__MODULE__{} = locator, index) when is_integer(index) do
    append(locator, {:nth, index})
  end

  def describe(%__MODULE__{} = locator) do
    Enum.map_join(locator.operations, " |> ", &describe_operation/1)
  end

  defp describe_operation({:css, css}), do: "by_css(#{inspect(css)})"

  defp describe_operation({:role, role, options}) do
    "by_role(#{inspect(role)}#{describe_options(options)})"
  end

  defp describe_operation({:text, text, options}) do
    "by_text(#{inspect(text)}#{describe_options(options)})"
  end

  defp describe_operation({:label, text, options}) do
    "by_label(#{inspect(text)}#{describe_options(options)})"
  end

  defp describe_operation({:attribute, attribute, text, options}) do
    function =
      case attribute do
        "placeholder" -> "by_placeholder"
        "alt" -> "by_alt_text"
        "title" -> "by_title"
      end

    "#{function}(#{inspect(text)}#{describe_options(options)})"
  end

  defp describe_operation({:test_id, "data-testid", test_id}) do
    "by_test_id(#{inspect(test_id)})"
  end

  defp describe_operation({:test_id, attribute, test_id}) do
    "by_test_id(#{inspect(test_id)}, attribute: #{inspect(attribute)})"
  end

  defp describe_operation({:filter, options}), do: "filter(#{describe_keywords(options)})"
  defp describe_operation({:nth, 0}), do: "nth(0)"
  defp describe_operation({:nth, -1}), do: "last()"
  defp describe_operation({:nth, index}), do: "nth(#{index})"

  defp describe_options([]), do: ""
  defp describe_options(options), do: ", " <> describe_keywords(options)

  defp describe_keywords(options) do
    Enum.map_join(options, ", ", fn
      {:has, %__MODULE__{} = locator} -> "has: " <> describe(locator)
      {key, value} -> "#{key}: #{inspect(value)}"
    end)
  end

  defp attribute_or_label_locator(:label, text, options) do
    new({:label, text, Options.validate_exact_locator!(options)})
  end

  defp attribute_locator(attribute, text, options) do
    new({:attribute, attribute, text, Options.validate_exact_locator!(options)})
  end

  defp append_attribute_locator(parent, attribute, text, options) do
    append(
      parent,
      {:attribute, attribute, text, Options.validate_exact_locator!(options)}
    )
  end

  defp validate_attribute!(attribute) when is_binary(attribute) do
    if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_.:-]*$/, attribute) do
      attribute
    else
      raise ArgumentError, "invalid test-id attribute name: #{inspect(attribute)}"
    end
  end
end

defimpl Inspect, for: Fluffy.Locator do
  import Inspect.Algebra

  def inspect(locator, _options) do
    concat(["#Fluffy.Locator<", Fluffy.Locator.describe(locator), ">"])
  end
end
