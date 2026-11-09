defmodule Fluffy.Locator.Static do
  @moduledoc false

  alias Fluffy.HTML.Aria
  alias Fluffy.Locator

  @labelled_control_selector "button, input, meter, output, progress, select, textarea"

  def resolve(document, %Locator{} = locator) do
    aria = if role_locator?(locator), do: Aria.for_document(document)
    resolve(aria, document, locator)
  end

  # `scope` is what the locator starts from; `aria` models the whole page, which
  # role and accessible-name computation looks across regardless of the scope.
  defp resolve(aria, scope, %Locator{} = locator) do
    Enum.reduce(locator.operations, [scope], fn
      {:and, right}, candidates ->
        matches = aria |> resolve(scope, right) |> MapSet.new(&LazyHTML.css_path/1)
        Enum.filter(candidates, &MapSet.member?(matches, LazyHTML.css_path(&1)))

      {:or, right}, candidates ->
        matches = MapSet.new(candidates ++ resolve(aria, scope, right), &LazyHTML.css_path/1)
        scope |> LazyHTML.query("*") |> Enum.filter(&MapSet.member?(matches, LazyHTML.css_path(&1)))

      {:role, role, options}, candidates ->
        role_matches(candidates, aria, role, options)

      {:filter, options}, candidates ->
        filter_candidates(candidates, aria, options)

      operation, candidates ->
        apply_operation(operation, candidates)
    end)
  end

  defp role_locator?(%Locator{operations: operations}), do: Enum.any?(operations, &role_operation?/1)

  defp role_operation?({:role, _role, _options}), do: true
  defp role_operation?({operator, %Locator{} = right}) when operator in [:and, :or], do: role_locator?(right)

  defp role_operation?({:filter, options}) do
    Enum.any?(options, fn
      {_option, %Locator{} = child} -> role_locator?(child)
      _option -> false
    end)
  end

  defp role_operation?(_operation), do: false

  # What Phoenix can know from markup: the element's own `hidden` or `aria-hidden`,
  # an ancestor's `hidden`, and hidden inputs, which a browser never renders.
  def structurally_visible?(element) do
    case LazyHTML.attributes(element) do
      [attributes] ->
        not hidden?(attributes) and not hidden_input?(element, attributes) and
          not hidden_ancestor?(LazyHTML.parent_node(element))

      _ ->
        true
    end
  end

  defp hidden_input?(element, attributes) do
    LazyHTML.tag(element) == ["input"] and String.downcase(attribute(attributes, "type") || "") == "hidden"
  end

  defp hidden_ancestor?(element) do
    case LazyHTML.attributes(element) do
      [attributes] -> has_attribute?(attributes, "hidden") or hidden_ancestor?(LazyHTML.parent_node(element))
      _ -> false
    end
  end

  defp apply_operation({:css, selector}, scopes) do
    query_scopes(scopes, selector)
  end

  defp apply_operation({:text, text, options}, scopes) do
    exact? = Keyword.get(options, :exact, false)

    candidates =
      scopes
      |> query_scopes("*")
      |> Enum.filter(&element_text_matches?(&1, text, exact?))

    Enum.reject(candidates, fn candidate ->
      candidate
      |> LazyHTML.query("*")
      |> Enum.drop(1)
      |> Enum.any?(&element_text_matches?(&1, text, exact?))
    end)
  end

  defp apply_operation({:label, text, options}, scopes) do
    exact? = Keyword.get(options, :exact, false)

    scopes
    |> Enum.flat_map(&labelled_controls(&1, text, exact?))
    |> Enum.uniq()
  end

  defp apply_operation({:attribute, attribute_name, text, options}, scopes) do
    exact? = Keyword.get(options, :exact, false)

    scopes
    |> query_scopes("[#{attribute_name}]")
    |> Enum.filter(fn element ->
      element
      |> element_attribute(attribute_name)
      |> attribute_matches?(text, exact?)
    end)
  end

  defp apply_operation({:test_id, attribute_name, test_id}, scopes) do
    scopes
    |> query_scopes("[#{attribute_name}]")
    |> Enum.filter(&(element_attribute(&1, attribute_name) == test_id))
  end

  defp apply_operation({:nth, index}, scopes) do
    case Enum.at(scopes, index) do
      nil -> []
      element -> [element]
    end
  end

  defp filter_candidates(candidates, aria, options) do
    Enum.filter(candidates, fn candidate ->
      Enum.all?(options, fn
        {:has_text, text} -> text_matches?(LazyHTML.text(candidate), text, Keyword.get(options, :exact, false))
        {:has_not_text, text} -> not text_matches?(LazyHTML.text(candidate), text, Keyword.get(options, :exact, false))
        {:visible, visible?} -> structurally_visible?(candidate) == visible?
        {:exact, _exact?} -> true
        {:has, %Locator{} = child} -> resolve(aria, candidate, child) != []
        {:has_not, %Locator{} = child} -> resolve(aria, candidate, child) == []
      end)
    end)
  end

  defp role_matches(scopes, aria, role, options) do
    role = role |> to_string() |> String.downcase()
    expected_name = Keyword.get(options, :name)
    exact? = Keyword.get(options, :exact, false)

    scopes
    |> Enum.flat_map(&Aria.scoped_nodes(aria, &1))
    |> Enum.uniq_by(fn {node, _element} -> node.id end)
    |> Enum.sort_by(fn {node, _element} -> node.id end)
    |> Enum.filter(fn {node, _element} ->
      Aria.role(aria, node) == role and not Aria.hidden?(aria, node) and
        accessible_name_matches?(aria, node, expected_name, exact?)
    end)
    |> Enum.map(fn {_node, element} -> element end)
  end

  defp accessible_name_matches?(_aria, _node, nil, _exact?), do: true

  defp accessible_name_matches?(aria, node, expected, exact?) do
    aria |> Aria.name(node) |> text_matches?(expected, exact?)
  end

  defp query_scopes(scopes, selector) do
    scopes
    |> Enum.flat_map(fn scope -> scope |> LazyHTML.query(selector) |> Enum.to_list() end)
    |> Enum.uniq()
  end

  defp labelled_controls(scope, expected, exact?) do
    controls = query_scopes([scope], @labelled_control_selector)

    html_labelled =
      scope
      |> LazyHTML.query("label")
      |> Enum.filter(&text_matches?(LazyHTML.text(&1), expected, exact?))
      |> Enum.flat_map(fn label ->
        case element_attribute(label, "for") do
          nil ->
            label
            |> LazyHTML.query(@labelled_control_selector)
            |> Enum.filter(&labelable?/1)
            |> Enum.take(1)

          id ->
            Enum.filter(controls, &(element_attribute(&1, "id") == id and labelable?(&1)))
        end
      end)
      |> Enum.reject(&has_author_label?/1)

    aria_labelled =
      [scope]
      |> query_scopes("[aria-label], [aria-labelledby]")
      |> Enum.filter(fn control ->
        case element_attribute(control, "aria-labelledby") do
          nil -> direct_label_matches?(control, expected, exact?)
          _references -> referenced_label_matches?(scope, control, expected, exact?)
        end
      end)

    html_labelled ++ aria_labelled
  end

  defp direct_label_matches?(control, expected, exact?) do
    case element_attribute(control, "aria-label") do
      nil -> false
      label -> text_matches?(label, expected, exact?)
    end
  end

  defp labelable?(control) do
    case LazyHTML.to_tree(control) do
      [{"input", attributes, _children}] ->
        String.downcase(attribute(attributes, "type") || "text") != "hidden"

      [{_tag, _attributes, _children}] ->
        true

      _other ->
        false
    end
  end

  defp has_author_label?(control) do
    element_attribute(control, "aria-labelledby") != nil or
      element_attribute(control, "aria-label") != nil
  end

  defp referenced_label_matches?(scope, control, expected, exact?) do
    case element_attribute(control, "aria-labelledby") do
      nil ->
        false

      ids ->
        references = String.split(ids)

        scope
        |> LazyHTML.query("[id]")
        |> Enum.any?(fn reference ->
          element_attribute(reference, "id") in references and
            text_matches?(LazyHTML.text(reference), expected, exact?)
        end)
    end
  end

  defp hidden?(attributes) do
    has_attribute?(attributes, "hidden") or
      String.downcase(attribute(attributes, "aria-hidden") || "false") == "true"
  end

  defp element_text_matches?(element, expected, exact?) do
    case element_tag_and_attributes(element) do
      {tag, _attributes} when tag in ["script", "style", "noscript"] ->
        false

      {"input", attributes} ->
        if attribute(attributes, "type") in ["button", "submit"] do
          text_matches?(attribute(attributes, "value") || "", expected, exact?)
        else
          false
        end

      {_tag, _attributes} ->
        text_matches?(LazyHTML.text(element), expected, exact?)
    end
  end

  defp element_tag_and_attributes(element) do
    case LazyHTML.to_tree(element) do
      [{tag, attributes, _children}] -> {tag, attributes}
      _other -> {nil, []}
    end
  end

  defp element_attribute(element, name) do
    case LazyHTML.attribute(element, name) do
      [value] -> value
      [] -> nil
    end
  end

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp has_attribute?(attributes, name), do: List.keymember?(attributes, name, 0)

  defp text_matches?(nil, _expected, _exact?), do: false

  defp text_matches?(actual, expected, true), do: normalize(actual) == normalize(expected)

  defp text_matches?(actual, expected, false) do
    actual
    |> normalize()
    |> String.downcase()
    |> String.contains?(expected |> normalize() |> String.downcase())
  end

  defp attribute_matches?(nil, _expected, _exact?), do: false
  defp attribute_matches?(actual, expected, true), do: actual == expected

  defp attribute_matches?(actual, expected, false) do
    String.contains?(String.downcase(actual), String.downcase(expected))
  end

  defp normalize(text) do
    text
    |> String.replace(~r/[\x{200B}\x{00AD}]/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
