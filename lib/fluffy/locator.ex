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

  alias Fluffy.FrameLocator
  alias Fluffy.Options

  @enforce_keys [:operations]
  defstruct operations: []

  @type t :: %__MODULE__{operations: [term()]}
  @type scope :: t() | FrameLocator.t()
  @type role_option :: unquote(NimbleOptions.option_typespec(Options.role_locator_schema()))
  @type exact_option :: unquote(NimbleOptions.option_typespec(Options.exact_locator_schema()))
  @type test_id_option :: unquote(NimbleOptions.option_typespec(Options.test_id_locator_schema()))
  @type filter_option :: unquote(NimbleOptions.option_typespec(Options.filter_locator_schema()))

  def new(operation), do: %__MODULE__{operations: [operation]}

  def append(%__MODULE__{} = locator, operation) do
    update_in(locator.operations, &(&1 ++ [operation]))
  end

  @spec by_role(atom(), [role_option()]) :: t()
  @spec by_role(scope(), atom()) :: t()
  @spec by_role(scope(), atom(), [role_option()]) :: t()
  def by_role(role, options \\ [])

  def by_role(role, options) when is_atom(role) and is_list(options) do
    new({:role, role, Options.validate_role_locator!(options)})
  end

  def by_role(parent, role) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_role(parent, role, [])
  end

  def by_role(parent, role, options)
      when (is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator)) and is_atom(role) and is_list(options) do
    child_query(parent, {:role, role, Options.validate_role_locator!(options)})
  end

  @spec by_text(String.t(), [exact_option()]) :: t()
  @spec by_text(scope(), String.t()) :: t()
  @spec by_text(scope(), String.t(), [exact_option()]) :: t()
  def by_text(text, options \\ [])

  def by_text(text, options) when is_binary(text) and is_list(options) do
    new({:text, text, Options.validate_exact_locator!(options)})
  end

  def by_text(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_text(parent, text, [])
  end

  def by_text(parent, text, options) when is_binary(text) and is_list(options) do
    child_query(parent, {:text, text, Options.validate_exact_locator!(options)})
  end

  @spec by_label(String.t(), [exact_option()]) :: t()
  @spec by_label(scope(), String.t()) :: t()
  @spec by_label(scope(), String.t(), [exact_option()]) :: t()
  def by_label(text, options \\ [])

  def by_label(text, options) when is_binary(text) and is_list(options) do
    attribute_or_label_locator(:label, text, options)
  end

  def by_label(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_label(parent, text, [])
  end

  def by_label(parent, text, options) when is_binary(text) and is_list(options) do
    child_query(parent, {:label, text, Options.validate_exact_locator!(options)})
  end

  @spec by_placeholder(String.t(), [exact_option()]) :: t()
  @spec by_placeholder(scope(), String.t()) :: t()
  @spec by_placeholder(scope(), String.t(), [exact_option()]) :: t()
  def by_placeholder(text, options \\ [])

  def by_placeholder(text, options) when is_binary(text) and is_list(options) do
    attribute_locator("placeholder", text, options)
  end

  def by_placeholder(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_placeholder(parent, text, [])
  end

  def by_placeholder(parent, text, options) when is_binary(text) and is_list(options) do
    append_attribute_locator(parent, "placeholder", text, options)
  end

  @spec by_alt_text(String.t(), [exact_option()]) :: t()
  @spec by_alt_text(scope(), String.t()) :: t()
  @spec by_alt_text(scope(), String.t(), [exact_option()]) :: t()
  def by_alt_text(text, options \\ [])

  def by_alt_text(text, options) when is_binary(text) and is_list(options) do
    attribute_locator("alt", text, options)
  end

  def by_alt_text(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_alt_text(parent, text, [])
  end

  def by_alt_text(parent, text, options) when is_binary(text) and is_list(options) do
    append_attribute_locator(parent, "alt", text, options)
  end

  @spec by_title(String.t(), [exact_option()]) :: t()
  @spec by_title(scope(), String.t()) :: t()
  @spec by_title(scope(), String.t(), [exact_option()]) :: t()
  def by_title(text, options \\ [])

  def by_title(text, options) when is_binary(text) and is_list(options) do
    attribute_locator("title", text, options)
  end

  def by_title(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_title(parent, text, [])
  end

  def by_title(parent, text, options) when is_binary(text) and is_list(options) do
    append_attribute_locator(parent, "title", text, options)
  end

  @spec by_test_id(String.t(), [test_id_option()]) :: t()
  @spec by_test_id(scope(), String.t()) :: t()
  @spec by_test_id(scope(), String.t(), [test_id_option()]) :: t()
  def by_test_id(test_id, options \\ [])

  def by_test_id(test_id, options) when is_binary(test_id) and is_list(options) do
    options = Options.validate_test_id_locator!(options)
    new({:test_id, validate_attribute!(options[:attribute]), test_id})
  end

  def by_test_id(parent, test_id) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_test_id(parent, test_id, [])
  end

  def by_test_id(parent, test_id, options) when is_binary(test_id) and is_list(options) do
    options = Options.validate_test_id_locator!(options)
    child_query(parent, {:test_id, validate_attribute!(options[:attribute]), test_id})
  end

  @spec by_css(String.t()) :: t()
  def by_css(css) when is_binary(css), do: new({:css, css})

  @spec by_css(scope(), String.t()) :: t()
  def by_css(parent, css) when is_binary(css) do
    child_query(parent, {:css, css})
  end

  @doc "Creates a lazy frame scope. Frame traversal requires the Playwright driver."
  @doc playwright_only: true
  @spec frame_locator(String.t()) :: FrameLocator.t()
  def frame_locator(css) when is_binary(css), do: css |> by_css() |> content_frame()

  @doc "Creates a nested frame scope relative to an element or frame query."
  @doc playwright_only: true
  @spec frame_locator(scope(), String.t()) :: FrameLocator.t()
  def frame_locator(parent, css) when is_binary(css), do: parent |> by_css(css) |> content_frame()

  @doc "Converts an iframe element query to a lazy query of its content frame."
  @doc playwright_only: true
  @spec content_frame(t()) :: FrameLocator.t()
  def content_frame(%__MODULE__{} = owner), do: %FrameLocator{owner: owner}

  @doc false
  def crosses_frame?(%__MODULE__{operations: operations}) do
    Enum.any?(operations, fn
      :enter_frame ->
        true

      {:filter, options} ->
        Enum.any?(options, fn
          {key, %__MODULE__{} = inner} when key in [:has, :has_not] -> crosses_frame?(inner)
          _ -> false
        end)

      _ ->
        false
    end)
  end

  defp child_query(%__MODULE__{} = parent, operation), do: append(parent, operation)

  defp child_query(%FrameLocator{owner: owner}, operation) do
    owner |> append(:enter_frame) |> append(operation)
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

  defp describe_operation(:enter_frame), do: "content_frame()"

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
    child_query(
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
