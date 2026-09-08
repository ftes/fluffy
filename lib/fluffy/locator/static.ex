defmodule Fluffy.Locator.Static do
  @moduledoc false

  alias Fluffy.Locator

  @labelled_control_selector "button, input, meter, output, progress, select, textarea"

  def resolve(document, %Locator{} = locator) do
    Enum.reduce(locator.operations, [document], &apply_operation/2)
  end

  def resolve_one!(document, %Locator{} = locator) do
    case resolve(document, locator) do
      [element] -> element
      candidates -> raise Fluffy.StrictnessError, locator: locator, candidates: candidates
    end
  end

  defp apply_operation({:css, selector}, scopes) do
    query_scopes(scopes, selector)
  end

  defp apply_operation({:role, role, options}, scopes) do
    expected_name = Keyword.get(options, :name)
    exact? = Keyword.get(options, :exact, false)

    scopes
    |> Enum.flat_map(&role_matches(&1, role, expected_name, exact?))
    |> Enum.uniq()
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

  defp apply_operation({:filter, options}, scopes) do
    Enum.filter(scopes, fn candidate ->
      Enum.all?(options, fn
        {:has_text, text} -> text_matches?(LazyHTML.text(candidate), text, false)
        {:has_not_text, text} -> not text_matches?(LazyHTML.text(candidate), text, false)
        {:has, %Locator{} = child} -> resolve(candidate, child) != []
        {:has_not, %Locator{} = child} -> resolve(candidate, child) == []
      end)
    end)
  end

  defp apply_operation({:nth, index}, scopes) do
    case Enum.at(scopes, index) do
      nil -> []
      element -> [element]
    end
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
      Enum.filter(controls, fn control ->
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

  defp role_matches(scope, expected_role, expected_name, exact?) do
    entries = structural_entries(scope)

    scope
    |> LazyHTML.query("*")
    |> Enum.zip(entries)
    |> Enum.filter(fn {_element, {tree, context}} ->
      not context.hidden? and element_role(tree) == to_string(expected_role) and
        accessible_name_matches?(tree, context, entries, expected_name, exact?)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp structural_entries(scope) do
    scope
    |> LazyHTML.to_tree()
    |> flatten_elements(%{hidden?: false, wrapping_labels: []})
  end

  defp flatten_elements(nodes, context) do
    Enum.flat_map(nodes, fn
      {tag, attributes, children} = tree ->
        hidden? = context.hidden? or hidden?(attributes)

        child_context = %{
          hidden?: hidden?,
          wrapping_labels:
            if(tag == "label",
              do: context.wrapping_labels ++ [accessible_node_text(tree)],
              else: context.wrapping_labels
            )
        }

        descendants =
          if tag == "template", do: [], else: flatten_elements(children, child_context)

        [{tree, %{context | hidden?: hidden?}} | descendants]

      _text ->
        []
    end)
  end

  defp hidden?(attributes) do
    has_attribute?(attributes, "hidden") or
      String.downcase(attribute(attributes, "aria-hidden") || "false") == "true"
  end

  defp element_role({tag, attributes, _children}) do
    case explicit_role(attributes) do
      role when role in ["none", "presentation"] -> nil
      nil -> implicit_role(tag, attributes)
      role -> role
    end
  end

  defp explicit_role(attributes) do
    case attribute(attributes, "role") do
      nil -> nil
      roles -> roles |> String.split() |> List.first()
    end
  end

  defp implicit_role("button", _attributes), do: "button"

  defp implicit_role(tag, _attributes) when tag in ["h1", "h2", "h3", "h4", "h5", "h6"], do: "heading"

  defp implicit_role("textarea", _attributes), do: "textbox"
  defp implicit_role("option", _attributes), do: "option"
  defp implicit_role(tag, _attributes) when tag in ["ul", "ol"], do: "list"
  defp implicit_role("li", _attributes), do: "listitem"
  defp implicit_role("table", _attributes), do: "table"
  defp implicit_role(tag, _attributes) when tag in ["thead", "tbody", "tfoot"], do: "rowgroup"
  defp implicit_role("tr", _attributes), do: "row"
  defp implicit_role("td", _attributes), do: "cell"

  defp implicit_role("th", attributes) do
    if String.downcase(attribute(attributes, "scope") || "") == "row",
      do: "rowheader",
      else: "columnheader"
  end

  defp implicit_role(tag, attributes) when tag in ["a", "area"] do
    if has_attribute?(attributes, "href"), do: "link"
  end

  defp implicit_role("img", attributes) do
    case attribute(attributes, "alt") do
      "" -> nil
      _alt -> "img"
    end
  end

  defp implicit_role("select", attributes) do
    multiple? = has_attribute?(attributes, "multiple")

    size =
      case Integer.parse(attribute(attributes, "size") || "1") do
        {value, ""} -> value
        _other -> 1
      end

    if multiple? or size > 1, do: "listbox", else: "combobox"
  end

  defp implicit_role("input", attributes) do
    case String.downcase(attribute(attributes, "type") || "text") do
      type when type in ["button", "image", "reset", "submit"] ->
        "button"

      "checkbox" ->
        "checkbox"

      "radio" ->
        "radio"

      "range" ->
        "slider"

      "number" ->
        "spinbutton"

      type when type in ["email", "search", "tel", "text", "url"] ->
        "textbox"

      type
      when type in [
             "checkbox",
             "color",
             "date",
             "datetime-local",
             "file",
             "hidden",
             "month",
             "password",
             "radio",
             "range",
             "reset",
             "submit",
             "time",
             "week"
           ] ->
        nil

      _invalid ->
        "textbox"
    end
  end

  defp implicit_role(_tag, _attributes), do: nil

  defp accessible_name_matches?(_tree, _context, _entries, nil, _exact?), do: true

  defp accessible_name_matches?(tree, context, entries, expected, exact?) do
    tree
    |> accessible_name(context, entries)
    |> text_matches?(expected, exact?)
  end

  defp accessible_name({tag, attributes, _children} = tree, context, entries) do
    referenced_name = referenced_name(attributes, entries)
    aria_label = attribute(attributes, "aria-label")
    native_labels = native_label_texts(tag, attributes, context, entries)

    cond do
      referenced_name != nil -> referenced_name
      aria_label != nil -> aria_label
      native_labels != [] -> Enum.join(native_labels, " ")
      tag == "img" -> attribute(attributes, "alt") || ""
      tag == "input" -> input_name(attributes)
      true -> content_or_title_name(tree, attributes)
    end
  end

  defp content_or_title_name(tree, attributes) do
    case tree |> accessible_node_text() |> normalize() do
      "" -> attribute(attributes, "title") || ""
      content -> content
    end
  end

  defp referenced_name(attributes, entries) do
    case attribute(attributes, "aria-labelledby") do
      nil ->
        nil

      ids ->
        names_by_id =
          Map.new(entries, fn
            {{_tag, reference_attributes, _children} = tree, _context} ->
              {attribute(reference_attributes, "id"), accessible_node_text(tree, true)}
          end)

        ids
        |> String.split()
        |> Enum.map_join(" ", &Map.get(names_by_id, &1, ""))
    end
  end

  defp native_label_texts(tag, attributes, context, entries)
       when tag in ["button", "input", "meter", "output", "progress", "select", "textarea"] do
    explicit =
      case attribute(attributes, "id") do
        nil ->
          []

        id ->
          Enum.flat_map(entries, fn
            {{"label", label_attributes, _children} = tree, _context} ->
              if attribute(label_attributes, "for") == id,
                do: [accessible_node_text(tree)],
                else: []

            _other ->
              []
          end)
      end

    explicit ++ context.wrapping_labels
  end

  defp native_label_texts(_tag, _attributes, _context, _entries), do: []

  defp input_name(attributes) do
    case String.downcase(attribute(attributes, "type") || "text") do
      "submit" -> attribute(attributes, "value") || "Submit"
      "reset" -> attribute(attributes, "value") || "Reset"
      type when type in ["button", "image"] -> attribute(attributes, "value") || ""
      _other -> ""
    end
  end

  defp accessible_node_text(tree, include_hidden_root? \\ false)

  defp accessible_node_text({_tag, attributes, children}, false) when is_list(attributes) do
    if hidden?(attributes), do: "", else: accessible_node_text_children(children)
  end

  defp accessible_node_text({_tag, _attributes, children}, _include_hidden_root?) do
    accessible_node_text_children(children)
  end

  defp accessible_node_text_children(children) do
    Enum.map_join(children, fn
      text when is_binary(text) -> text
      {_tag, _attributes, _children} = child -> accessible_node_text(child)
      _other -> ""
    end)
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
