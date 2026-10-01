defmodule Fluffy.ClientDOM.Query do
  @moduledoc false

  alias Fluffy.HTML.DocumentIndex
  alias Fluffy.Locator
  alias Fluffy.Locator.Static

  # Ignore strings, comments and escaped characters when replacing pseudo-classes.
  @css_tokens ~r/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\/\*.*?\*\/|\\.|:checked(?![\w-])/is

  def resolve(document, locator, checked_ids) do
    marker = "data-fluffy-checked-#{System.unique_integer([:positive, :monotonic])}"
    rewritten = rewrite(locator, marker)

    if rewritten == locator do
      Static.resolve(document, locator)
    else
      # Project current user-input state for this query only. Keep the rendered
      # attributes intact: [checked]/[selected] describe defaults, :checked the
      # current property. Return original nodes so actions and diagnostics never
      # observe the private marker or a replacement document.
      {tree, _next_id} = document |> LazyHTML.to_tree() |> mark(checked_ids.(), marker, 0)
      original_nodes = Map.new(LazyHTML.query(document, "*"), &{DocumentIndex.path(&1), &1})

      tree
      |> LazyHTML.from_tree()
      |> Static.resolve(rewritten)
      |> Enum.map(&Map.fetch!(original_nodes, DocumentIndex.path(&1)))
    end
  end

  defp rewrite(%Locator{} = locator, marker) do
    %{locator | operations: Enum.map(locator.operations, &rewrite_operation(&1, marker))}
  end

  defp rewrite_operation({:css, selector}, marker) do
    selector =
      Regex.replace(@css_tokens, selector, fn token ->
        if String.downcase(token) == ":checked", do: "[#{marker}]", else: token
      end)

    {:css, selector}
  end

  defp rewrite_operation({:filter, options}, marker) do
    {:filter,
     Enum.map(options, fn
       {key, %Locator{} = child} -> {key, rewrite(child, marker)}
       option -> option
     end)}
  end

  defp rewrite_operation(operation, _marker), do: operation

  # DocumentIndex assigns IDs in element preorder, including inert descendants.
  defp mark(nodes, checked_ids, marker, next_id) do
    Enum.map_reduce(nodes, next_id, fn
      {tag, attributes, children}, id when is_binary(tag) ->
        attributes = if MapSet.member?(checked_ids, id), do: [{marker, ""} | attributes], else: attributes
        {children, next_id} = mark(children, checked_ids, marker, id + 1)
        {{tag, attributes, children}, next_id}

      node, id ->
        {node, id}
    end)
  end
end
