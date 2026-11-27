defmodule Fluffy.Driver.Phoenix.ClientDOM.Diagnostics do
  @moduledoc false

  alias Fluffy.Driver.Phoenix.ClientDOM
  alias Fluffy.Driver.Phoenix.HTML.Aria
  alias Fluffy.Driver.Phoenix.HTML.Semantics
  alias Fluffy.Driver.Phoenix.Locator, as: PhoenixLocator
  alias Fluffy.Expect.Internal
  alias Fluffy.StrictnessError
  alias Playwright.Isomorphic.StringUtils

  def missing_assertion(client_dom, locator) do
    case diagnostic_query(locator) do
      {:role, _, _, _} = query ->
        "No element matched." <> other_names(client_dom, query)

      _ ->
        text = client_dom.document |> Semantics.document_text() |> StringUtils.normalize_white_space()
        "No element matched.\nPage text: #{inspect(text, printable_limit: 500)}"
    end
  end

  def missing_action(client_dom, %StrictnessError{candidates: []} = error) do
    detail =
      case diagnostic_query(error.locator) do
        {:role, _, _, _} = query -> other_names(client_dom, query)
        {:label, text, options, scope} -> label_evidence(client_dom, scope, text, options)
        nil -> before_filter(client_dom, error.locator)
      end

    %{error | message: error.message <> detail}
  end

  defp before_filter(client_dom, locator) do
    with {{:filter, [has_text: _]}, prefix} <- List.pop_at(locator.operations, -1),
         [_ | _] = matches <- ClientDOM.resolve(client_dom, %{locator | operations: prefix}) do
      "\n" <> Fluffy.Expectation.candidate_section(matches, "Matches before filter")
    else
      _ -> ""
    end
  end

  # Relax only the terminal query, retaining its roots even inside within/2.
  defp diagnostic_query(locator) do
    case List.pop_at(locator.operations, -1) do
      {{:role, role, options}, scope} ->
        other = %{locator | operations: scope ++ [{:role, role, Keyword.delete(options, :name)}]}
        {:role, role, options, other}

      {{:label, text, options}, scope} ->
        {:label, text, options, %{locator | operations: scope}}

      {{:within, parent, child}, scope} ->
        with {kind, expected, options, other} <- diagnostic_query(child) do
          {kind, expected, options, %{locator | operations: scope ++ [{:within, parent, other}]}}
        end

      _ ->
        nil
    end
  end

  defp other_names(client_dom, {:role, role, options, other}) do
    if Keyword.has_key?(options, :name) do
      aria = Aria.for_document(client_dom.document)

      names =
        client_dom
        |> ClientDOM.resolve(other)
        |> Enum.take(5)
        |> Enum.map_join(", ", fn element ->
          node = Aria.node_for(aria, element)
          inspect(Aria.name(aria, node, options[:include_hidden] || false), printable_limit: 180)
        end)

      if names == "", do: "", else: " Other #{role} names in scope: #{names}"
    else
      ""
    end
  end

  defp label_evidence(client_dom, scope, text, options) do
    aria = Aria.for_document(client_dom.document)

    nodes =
      client_dom
      |> ClientDOM.resolve(scope)
      |> PhoenixLocator.scoped_nodes(aria)
      |> Enum.map(&elem(&1, 0))

    expected = Internal.compile(text)
    exact? = Keyword.get(options, :exact, false)

    orphan =
      Enum.find(nodes, fn node ->
        node.tag == "label" and PhoenixLocator.text_matches?(Semantics.text(node), expected, exact?) and
          is_nil(Aria.label_control_id(aria, node))
      end)

    labels =
      nodes
      |> Stream.flat_map(&Aria.element_labels(aria, &1))
      |> Stream.map(&StringUtils.normalize_white_space/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.uniq()
      |> Enum.take(5)

    orphan_detail(orphan) <> other_labels(labels)
  end

  defp orphan_detail(nil), do: ""

  defp orphan_detail(node) do
    text = node |> Semantics.text() |> StringUtils.normalize_white_space()
    " A matching label (#{inspect(text, printable_limit: 180)}) has no associated control."
  end

  defp other_labels([]), do: ""

  defp other_labels(labels),
    do: " Other labels in scope: " <> Enum.map_join(labels, ", ", &inspect(&1, printable_limit: 180))
end
