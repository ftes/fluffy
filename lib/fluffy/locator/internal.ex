defmodule Fluffy.Locator.Internal do
  @moduledoc false
  # Builds and inspects `Fluffy.Locator` operations, outside the module that
  # `import Fluffy.Locator` brings into tests.

  alias Fluffy.Locator
  alias Fluffy.Options

  @doc "A locator of one operation."
  def new(operation), do: %Locator{operations: [operation]}

  @doc "Appends an operation to `locator`."
  def append(%Locator{} = locator, operation) do
    update_in(locator.operations, &(&1 ++ [operation]))
  end

  @doc """
  `locator` as if built from `scope`. Operands of `and_/2` and `or_/2` resolve from
  the query root, so they are scoped too. A locator that enters a frame and has such
  an operand, or one of `has:` or `has_not:`, is rejected: `scope` does not apply
  inside the frame, so it could only match nothing.
  """
  def within(%Locator{} = scope, %Locator{operations: operations} = locator) do
    if crosses_frame?(locator) and Enum.any?(operations, &composed?/1) do
      raise ArgumentError,
            "within/3 cannot scope a frame locator combined with and_, or_, has:, has_not: or label:, " <>
              "got: #{describe(locator)}"
    end

    %Locator{operations: scope.operations ++ Enum.map(operations, &within_operation(scope, &1))}
  end

  defp within_operation(scope, {operator, %Locator{} = right}) when operator in [:and, :or],
    do: {operator, within(scope, right)}

  defp within_operation(_scope, operation), do: operation

  defp composed?({operator, %Locator{}}) when operator in [:and, :or], do: true
  defp composed?({:filter, options}), do: Keyword.has_key?(options, :has) or Keyword.has_key?(options, :has_not)
  defp composed?(_operation), do: false

  @doc "Whether `locator` or a nested locator enters a frame."
  def crosses_frame?(%Locator{operations: operations}) do
    Enum.any?(operations, fn
      :enter_frame ->
        true

      {operator, inner} when operator in [:and, :or] ->
        crosses_frame?(inner)

      {:filter, options} ->
        Enum.any?(options, fn
          {key, %Locator{} = inner} when key in [:has, :has_not] -> crosses_frame?(inner)
          _ -> false
        end)

      _ ->
        false
    end)
  end

  @doc """
  The first `{key, value}` option of `locator` or a nested locator that only Playwright
  honors, or nil.
  """
  def playwright_option(%Locator{operations: operations}) do
    Enum.find_value(operations, fn
      {:role, _role, options} -> playwright_option(options)
      {:filter, options} -> playwright_option(options)
      {operator, %Locator{} = inner} when operator in [:and, :or] -> playwright_option(inner)
      _operation -> nil
    end)
  end

  def playwright_option(options) when is_list(options) do
    Enum.find_value(options, fn
      {key, %Locator{} = inner} when key in [:has, :has_not] ->
        playwright_option(inner)

      {key, value} = option ->
        if key in Options.playwright_locator_keys() or
             (is_struct(value, Regex) and key in Options.playwright_regex_locator_keys()),
           do: option
    end)
  end

  @doc "Renders `locator` as the Fluffy calls that build it."
  def describe(%Locator{} = locator) do
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

  defp describe_operation({:or, right}), do: "or_(#{describe(right)})"

  defp describe_operation({:and, right}), do: "and_(#{describe(right)})"

  defp describe_operation({:filter, options}), do: "filter(#{describe_keywords(options)})"
  defp describe_operation({:nth, 0}), do: "nth(0)"
  defp describe_operation({:nth, -1}), do: "last()"
  defp describe_operation({:nth, index}), do: "nth(#{index})"

  defp describe_options([]), do: ""
  defp describe_options(options), do: ", " <> describe_keywords(options)

  defp describe_keywords(options) do
    Enum.map_join(options, ", ", fn
      {:has, %Locator{} = locator} -> "has: " <> describe(locator)
      {key, value} -> "#{key}: #{inspect(value)}"
    end)
  end
end
