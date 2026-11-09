defmodule Fluffy.HTML.Aria do
  @moduledoc false

  # Playwright's role and accessible-name computation (roleUtils in its injected
  # script) over parsed markup. Computed CSS stays browser-only: visibility and
  # inline display come from each tag's user-agent defaults.

  alias Fluffy.HTML.DocumentIndex
  alias Fluffy.HTML.Semantics

  @enforce_keys [:document, :nodes, :roots, :html_ids, :labels]
  defstruct @enforce_keys

  @valid_roles ~w(
    alert alertdialog application article banner blockquote button caption cell checkbox code
    columnheader combobox complementary contentinfo definition deletion dialog directory document
    emphasis feed figure form generic grid gridcell group heading img insertion link list listbox
    listitem log main mark marquee math meter menu menubar menuitem menuitemcheckbox menuitemradio
    navigation none note option paragraph presentation progressbar radio radiogroup region row
    rowgroup rowheader scrollbar search searchbox separator slider spinbutton status strong
    subscript superscript switch tab table tablist tabpanel term textbox time timer toolbar tooltip
    tree treegrid treeitem
  )

  @presentation_roles ["none", "presentation"]

  @tag_roles %{
    "article" => "article",
    "aside" => "complementary",
    "blockquote" => "blockquote",
    "button" => "button",
    "caption" => "caption",
    "code" => "code",
    "datalist" => "listbox",
    "dd" => "definition",
    "del" => "deletion",
    "details" => "group",
    "dfn" => "term",
    "dialog" => "dialog",
    "dt" => "term",
    "em" => "emphasis",
    "fieldset" => "group",
    "figure" => "figure",
    "h1" => "heading",
    "h2" => "heading",
    "h3" => "heading",
    "h4" => "heading",
    "h5" => "heading",
    "h6" => "heading",
    "hr" => "separator",
    "html" => "document",
    "ins" => "insertion",
    "li" => "listitem",
    "main" => "main",
    "mark" => "mark",
    "math" => "math",
    "menu" => "list",
    "meter" => "meter",
    "nav" => "navigation",
    "ol" => "list",
    "optgroup" => "group",
    "option" => "option",
    "output" => "status",
    "p" => "paragraph",
    "progress" => "progressbar",
    "search" => "search",
    "strong" => "strong",
    "sub" => "subscript",
    "sup" => "superscript",
    "svg" => "img",
    "table" => "table",
    "tbody" => "rowgroup",
    "textarea" => "textbox",
    "tfoot" => "rowgroup",
    "thead" => "rowgroup",
    "time" => "time",
    "tr" => "row",
    "ul" => "list"
  }

  @input_roles %{
    "button" => "button",
    "checkbox" => "checkbox",
    "image" => "button",
    "number" => "spinbutton",
    "radio" => "radio",
    "range" => "slider",
    "reset" => "button",
    "submit" => "button"
  }

  # A `header` or `footer` inside one of these belongs to it, not to the page.
  @sectioning_tags ["article", "aside", "main", "nav", "section"]
  @sectioning_roles ["article", "complementary", "main", "navigation", "region"]

  # An implicit role is presentational when these parents up the chain are.
  @presentation_parents %{
    "dd" => ["dl", "div"],
    "div" => ["dl"],
    "dt" => ["dl", "div"],
    "li" => ["ol", "ul"],
    "tbody" => ["table"],
    "td" => ["tr"],
    "tfoot" => ["table"],
    "th" => ["tr"],
    "thead" => ["table"],
    "tr" => ["thead", "tbody", "tfoot", "table"]
  }

  @global_aria_attributes ~w(
    aria-atomic aria-busy aria-controls aria-current aria-describedby aria-details aria-dropeffect
    aria-flowto aria-grabbed aria-hidden aria-keyshortcuts aria-live aria-owns aria-relevant
  )
  @naming_attributes ["aria-label", "aria-labelledby"]
  @roles_prohibiting_naming_attributes ~w(
    caption code deletion emphasis generic insertion paragraph presentation strong subscript superscript
  )

  # Not a JavaScript number (NaN) means no tabindex, the empty string is 0.
  @js_number ~r/^\s*(?:[+-]?(?:\d+\.?\d*(?:e[+-]?\d+)?|\.\d+(?:e[+-]?\d+)?|Infinity)|0x[0-9a-f]+|0o[0-7]+|0b[01]+)?\s*$/iu

  @naming_prohibited_roles ~w(
    caption code definition deletion emphasis generic insertion mark paragraph presentation strong
    subscript suggestion superscript term time
  )
  @name_from_content_roles ~w(
    button cell checkbox columnheader gridcell heading link menuitem menuitemcheckbox menuitemradio
    option radio row rowheader switch tab tooltip treeitem
  )
  @name_from_content_descendant_roles [
    ""
    | ~w(
      caption code contentinfo definition deletion emphasis insertion list listitem mark none
      paragraph presentation region row rowgroup section strong subscript superscript table term time
    )
  ]

  @labelable_tags ~w(button input meter output progress select textarea)
  @ignored_tags ~w(script style noscript template)

  # Display none in the user-agent stylesheet.
  @not_rendered_tags ~w(area base datalist head link meta noembed noframes param rp script style template title)
  # SVG's own metadata has no box, and keeps display inline.
  @svg_metadata_tags ~w(desc metadata)
  # A replaced element renders its own content, not its element children.
  @fallback_content_tags ~w(audio canvas meter option progress video)
  # Anything else but display inline separates its text from its neighbours'.
  @non_inline_tags @not_rendered_tags ++
                     ~w(
                       address article aside blockquote body br button caption center col colgroup dd
                       details dialog dir div dl dt fieldset figcaption figure footer form h1 h2 h3 h4
                       h5 h6 header hgroup hr html input legend li listing main marquee menu meter nav
                       ol optgroup option p plaintext pre progress ruby search section select slot
                       summary table tbody td textarea tfoot th thead tr ul xmp
                     )

  @context %{target: nil, labelled_by: nil, label: nil, native: nil}

  def new(%LazyHTML{} = document) do
    {roots, {nodes, _next_id}} = document |> LazyHTML.to_tree() |> add_children(nil, {%{}, 0})
    aria = %__MODULE__{document: document, nodes: nodes, roots: roots, html_ids: %{}, labels: %{}}
    aria = %{aria | html_ids: html_ids(aria)}
    %{aria | labels: labels_by_control(aria)}
  end

  # The node and element of everything a locator's scope can match, in document
  # order. A scope is never one of its own matches.
  def scoped_nodes(%__MODULE__{} = aria, scope) do
    elements = scope |> LazyHTML.query("*") |> Enum.to_list()

    if scope == aria.document do
      Enum.zip(all_nodes(aria), elements)
    else
      scope_node = node_at(aria, DocumentIndex.path(scope))
      aria |> descendants(scope_node) |> Enum.zip(Enum.drop(elements, 1))
    end
  end

  def hidden?(%__MODULE__{} = aria, node) do
    ignored?(aria, node) or dropdown_optgroup?(aria, node) or closest(aria, node, &not_rendered?(aria, &1)) != nil
  end

  def role(%__MODULE__{} = aria, node) do
    explicit = explicit_role(node)

    cond do
      explicit == nil -> implicit_role(aria, node)
      explicit in @presentation_roles -> presentation_role(aria, node, explicit)
      true -> explicit
    end
  end

  def name(%__MODULE__{} = aria, node) do
    if (role(aria, node) || "") in @naming_prohibited_roles do
      ""
    else
      {text, _visited} = text_alternative(aria, node, %{@context | target: :self}, MapSet.new())
      text
    end
  end

  defp add_children(trees, parent_id, accumulator) do
    Enum.flat_map_reduce(trees, accumulator, &add_node(&1, parent_id, &2))
  end

  defp add_node(text, _parent_id, accumulator) when is_binary(text), do: {[text], accumulator}

  defp add_node({tag, attributes, children}, parent_id, {nodes, id}) when is_binary(tag) do
    # A template's content is not part of the document.
    children = if tag == "template", do: [], else: children
    {child_ids, {nodes, next_id}} = add_children(children, id, {nodes, id + 1})

    node = %{id: id, tag: tag, attributes: attributes, parent: parent_id, children: child_ids, last: next_id - 1}
    {[id], {Map.put(nodes, id, node), next_id}}
  end

  defp add_node(_comment, _parent_id, accumulator), do: {[], accumulator}

  defp html_ids(aria) do
    aria
    |> all_nodes()
    |> Enum.reject(&inert?(aria, &1))
    |> Enum.reduce(%{}, fn node, html_ids ->
      case attribute(node, "id") do
        nil -> html_ids
        html_id -> Map.put_new(html_ids, html_id, node.id)
      end
    end)
  end

  defp labels_by_control(aria) do
    aria
    |> all_nodes()
    |> Enum.filter(&(&1.tag == "label" and not inert?(aria, &1)))
    |> Enum.group_by(&labeled_control_id(aria, &1), & &1.id)
  end

  defp labeled_control_id(aria, label) do
    case attribute(label, "for") do
      nil -> aria |> descendants(label) |> Enum.find(&labelable?/1) |> then(&(&1 && &1.id))
      html_id -> labelable_id(aria, Map.get(aria.html_ids, html_id))
    end
  end

  defp labelable_id(_aria, nil), do: nil

  defp labelable_id(aria, id) do
    if aria |> fetch(id) |> labelable?(), do: id
  end

  defp labelable?(%{tag: "input"} = node), do: Semantics.input_type(node) != "hidden"
  defp labelable?(%{tag: tag}), do: tag in @labelable_tags

  defp all_nodes(aria), do: Enum.map(0..(map_size(aria.nodes) - 1)//1, &fetch(aria, &1))

  defp descendants(aria, node), do: Enum.map((node.id + 1)..node.last//1, &fetch(aria, &1))

  defp fetch(aria, id), do: Map.fetch!(aria.nodes, id)

  defp parent(_aria, %{parent: nil}), do: nil
  defp parent(aria, %{parent: parent_id}), do: fetch(aria, parent_id)

  defp child_elements(aria, node) do
    node.children |> Enum.filter(&is_integer/1) |> Enum.map(&fetch(aria, &1))
  end

  defp first_child(aria, node, tag), do: aria |> child_elements(node) |> Enum.find(&(&1.tag == tag))

  defp closest(_aria, nil, _predicate), do: nil

  defp closest(aria, node, predicate) do
    if predicate.(node), do: node, else: closest(aria, parent(aria, node), predicate)
  end

  defp node_at(aria, path), do: descend(aria, %{children: aria.roots}, path)

  defp descend(_aria, node, []), do: node

  defp descend(aria, node, [{_tag, position} | path]) do
    id = node.children |> Enum.filter(&is_integer/1) |> Enum.at(position - 1)
    descend(aria, fetch(aria, id), path)
  end

  defp attribute(node, name), do: Semantics.attribute(node.attributes, name)

  defp attribute?(node, name), do: Semantics.has_attribute?(node.attributes, name)

  defp text_attribute(node, name), do: attribute(node, name) || ""

  defp non_blank_attribute(node, names) do
    Enum.find_value(names, &if(not blank?(text_attribute(node, &1)), do: attribute(node, &1)))
  end

  defp blank?(text), do: String.trim(text) == ""

  defp not_rendered?(aria, node) do
    hidden_attribute?(node) or String.downcase(text_attribute(node, "aria-hidden")) == "true" or
      node.tag in @not_rendered_tags or node.tag in @svg_metadata_tags or closed_by_state?(node) or
      closed_by_parent?(aria, node)
  end

  # The user-agent's [hidden] rule covers HTML only, and marquee's display overrides it.
  # until-found keeps the element's own box and hides only its content.
  defp hidden_attribute?(node) do
    attribute?(node, "hidden") and text_attribute(node, "hidden") != "until-found" and
      node.tag not in ["marquee", "math", "svg"]
  end

  defp closed_by_state?(%{tag: "dialog"} = node), do: not attribute?(node, "open")
  defp closed_by_state?(%{tag: "audio"} = node), do: not attribute?(node, "controls")
  defp closed_by_state?(%{tag: "input"} = node), do: Semantics.input_type(node) == "hidden"
  defp closed_by_state?(_node), do: false

  defp closed_by_parent?(aria, node) do
    case parent(aria, node) do
      %{tag: tag} when tag in @fallback_content_tags ->
        true

      %{tag: "details"} = details ->
        not attribute?(details, "open") and first_child(aria, details, "summary") != node

      %{} = parent ->
        text_attribute(parent, "hidden") == "until-found"

      nil ->
        false
    end
  end

  # Only a list box renders its groups; a dropdown shows its options on its own.
  defp dropdown_optgroup?(aria, %{tag: "optgroup"} = node) do
    case parent(aria, node) do
      %{tag: "select"} = select -> not list_box?(select)
      _other -> false
    end
  end

  defp dropdown_optgroup?(_aria, _node), do: false

  defp ignored?(aria, node), do: node.tag in @ignored_tags or inert?(aria, node)

  # A browser parses noscript's content as text.
  defp inert?(aria, node) do
    closest(aria, parent(aria, node), &(&1.tag == "noscript")) != nil
  end

  defp explicit_role(node) do
    node
    |> text_attribute("role")
    |> String.downcase()
    |> String.split(" ")
    |> Enum.map(&String.trim/1)
    |> Enum.find(&(&1 in @valid_roles))
  end

  defp presentation_role(aria, node, explicit) do
    implicit = implicit_role(aria, node)
    if presentation_conflict?(aria, node, implicit), do: implicit, else: explicit
  end

  defp presentation_conflict?(aria, node, role), do: global_aria_attribute?(node, role) or focusable?(aria, node)

  defp global_aria_attribute?(node, role) do
    Enum.any?(@global_aria_attributes, &attribute?(node, &1)) or
      (role not in @roles_prohibiting_naming_attributes and Enum.any?(@naming_attributes, &attribute?(node, &1))) or
      (role != "generic" and attribute?(node, "aria-roledescription"))
  end

  defp focusable?(aria, node) do
    not natively_disabled?(aria, node) and (natively_focusable?(node) or tabindex?(node))
  end

  defp natively_focusable?(%{tag: tag}) when tag in ["button", "details", "select", "textarea"], do: true
  defp natively_focusable?(%{tag: tag} = node) when tag in ["a", "area"], do: attribute?(node, "href")
  defp natively_focusable?(%{tag: "input"} = node), do: not attribute?(node, "hidden")
  defp natively_focusable?(_node), do: false

  defp tabindex?(node) do
    case attribute(node, "tabindex") do
      nil -> false
      value -> value =~ @js_number
    end
  end

  defp natively_disabled?(aria, %{tag: tag} = node)
       when tag in ["button", "input", "select", "textarea", "option", "optgroup"] do
    attribute?(node, "disabled") or disabled_option_group?(aria, node) or disabled_field_set?(aria, node)
  end

  defp natively_disabled?(_aria, _node), do: false

  defp disabled_option_group?(aria, %{tag: "option"} = node) do
    closest(aria, node, &(&1.tag == "optgroup" and attribute?(&1, "disabled"))) != nil
  end

  defp disabled_option_group?(_aria, _node), do: false

  defp disabled_field_set?(aria, node) do
    case closest(aria, node, &(&1.tag == "fieldset" and attribute?(&1, "disabled"))) do
      nil ->
        false

      field_set ->
        legend = first_child(aria, field_set, "legend")
        legend == nil or node.id not in legend.id..legend.last
    end
  end

  defp implicit_role(aria, node) do
    case tag_role(aria, node) do
      nil -> nil
      role -> inherited_presentation_role(aria, node) || role
    end
  end

  defp inherited_presentation_role(aria, node) do
    parent = parent(aria, node)

    if parent && parent.tag in Map.get(@presentation_parents, node.tag, []) do
      explicit = explicit_role(parent)

      if explicit in @presentation_roles and not presentation_conflict?(aria, parent, explicit),
        do: explicit,
        else: inherited_presentation_role(aria, parent)
    end
  end

  defp tag_role(_aria, %{tag: tag} = node) when tag in ["a", "area"] do
    if attribute?(node, "href"), do: "link"
  end

  defp tag_role(aria, %{tag: "header"} = node), do: page_landmark(aria, node, "banner")
  defp tag_role(aria, %{tag: "footer"} = node), do: page_landmark(aria, node, "contentinfo")
  defp tag_role(_aria, %{tag: "form"} = node), do: if(explicitly_named?(node), do: "form")
  defp tag_role(_aria, %{tag: "section"} = node), do: if(explicitly_named?(node), do: "region")

  defp tag_role(_aria, %{tag: "img"} = node) do
    if attribute(node, "alt") == "" and text_attribute(node, "title") == "" and not global_aria_attribute?(node, nil) and
         not tabindex?(node),
       do: "presentation",
       else: "img"
  end

  defp tag_role(aria, %{tag: "input"} = node) do
    case Semantics.input_type(node) do
      type when type in ["email", "search", "tel", "text", "url"] -> text_input_role(aria, node, type)
      "hidden" -> nil
      "file" -> "button"
      type -> Map.get(@input_roles, type, "textbox")
    end
  end

  defp tag_role(_aria, %{tag: "select"} = node), do: if(list_box?(node), do: "listbox", else: "combobox")

  defp tag_role(aria, %{tag: "td"} = node) do
    table = closest(aria, node, &(&1.tag == "table"))
    if table && explicit_role(table) in ["grid", "treegrid"], do: "gridcell", else: "cell"
  end

  defp tag_role(aria, %{tag: "th"} = node) do
    case attribute(node, "scope") do
      scope when scope in ["col", "colgroup"] -> "columnheader"
      scope when scope in ["row", "rowgroup"] -> "rowheader"
      _other -> inferred_header_role(aria, node)
    end
  end

  defp tag_role(_aria, %{tag: tag}), do: Map.get(@tag_roles, tag)

  defp page_landmark(aria, node, role) do
    if closest(aria, parent(aria, node), &sectioning?/1) == nil, do: role
  end

  defp sectioning?(node) do
    case attribute(node, "role") do
      nil -> node.tag in @sectioning_tags
      role -> role in @sectioning_roles
    end
  end

  defp explicitly_named?(node), do: Enum.any?(@naming_attributes, &attribute?(node, &1))

  defp text_input_role(aria, node, type) do
    case references(aria, node, "list") do
      [list_id | _rest] ->
        if fetch(aria, list_id).tag == "datalist", do: "combobox", else: text_input_role(type)

      [] ->
        text_input_role(type)
    end
  end

  defp text_input_role("search"), do: "searchbox"
  defp text_input_role(_type), do: "textbox"

  defp list_box?(select) do
    attribute?(select, "multiple") or
      case select |> text_attribute("size") |> String.trim_leading() |> Integer.parse() do
        {size, _rest} -> size > 1
        :error -> false
      end
  end

  defp inferred_header_role(aria, node) do
    {previous, next} = adjacent_elements(aria, node)

    cond do
      previous == nil and next == nil -> if only_row?(aria, node), do: nil, else: "columnheader"
      header_cell?(previous) and header_cell?(next) -> "columnheader"
      non_empty_data_cell?(aria, previous) or non_empty_data_cell?(aria, next) -> "rowheader"
      true -> "columnheader"
    end
  end

  defp adjacent_elements(aria, node) do
    siblings =
      case parent(aria, node) do
        nil -> aria.roots |> Enum.filter(&is_integer/1) |> Enum.map(&fetch(aria, &1))
        parent -> child_elements(aria, parent)
      end

    index = Enum.find_index(siblings, &(&1.id == node.id))
    {if(index > 0, do: Enum.at(siblings, index - 1)), Enum.at(siblings, index + 1)}
  end

  defp header_cell?(node), do: node != nil and node.tag == "th"

  defp non_empty_data_cell?(_aria, nil), do: false

  defp non_empty_data_cell?(aria, node) do
    node.tag == "td" and (child_elements(aria, node) != [] or not blank?(text_content(aria, node)))
  end

  defp only_row?(aria, node) do
    with %{tag: "tr"} = row <- parent(aria, node),
         %{} = table <- closest(aria, row, &(&1.tag == "table")) do
      table_row_count(aria, table) <= 1
    else
      _no_row_or_table -> false
    end
  end

  defp table_row_count(aria, table) do
    aria
    |> child_elements(table)
    |> Enum.flat_map(fn child -> if child.tag == "tr", do: [child], else: table_section_rows(aria, child) end)
    |> length()
  end

  defp table_section_rows(aria, %{tag: tag} = section) when tag in ["thead", "tbody", "tfoot"] do
    aria |> child_elements(section) |> Enum.filter(&(&1.tag == "tr"))
  end

  defp table_section_rows(_aria, _child), do: []

  defp references(aria, node, attribute) do
    node
    |> text_attribute(attribute)
    |> String.split(~r/[ \t\n\f\r]+/, trim: true)
    |> Enum.flat_map(&List.wrap(Map.get(aria.html_ids, &1)))
    |> Enum.uniq()
  end

  defp text_alternative(aria, node, context, visited) do
    cond do
      MapSet.member?(visited, node.id) ->
        {"", visited}

      ignored?(aria, node) or (hidden?(aria, node) and not hidden_reference?(context)) ->
        {"", MapSet.put(visited, node.id)}

      true ->
        referenced_or_own_name(aria, node, references(aria, node, "aria-labelledby"), context, visited)
    end
  end

  defp hidden_reference?(context), do: :hidden in [context.labelled_by, context.label, context.native]

  defp visibility(aria, node), do: if(hidden?(aria, node), do: :hidden, else: :visible)

  defp referenced_or_own_name(aria, node, references, context, visited) do
    {name, visited} =
      if context.labelled_by do
        {"", visited}
      else
        {parts, visited} =
          alternatives(aria, references, &%{@context | labelled_by: visibility(aria, &1)}, visited)

        {Enum.join(parts, " "), visited}
      end

    if name == "" do
      own_name(aria, node, references, context, MapSet.put(visited, node.id))
    else
      {name, visited}
    end
  end

  defp alternatives(aria, ids, context_for, visited) do
    Enum.map_reduce(ids, visited, fn id, visited ->
      node = fetch(aria, id)
      text_alternative(aria, node, context_for.(node), visited)
    end)
  end

  defp own_name(aria, node, references, context, visited) do
    role = role(aria, node) || ""

    with nil <- embedded_widget_value(aria, node, role, references, context, visited),
         nil <- aria_label(node, visited),
         nil <- native_name_unless_presentational(aria, node, role, references, context, visited) do
      content_or_title(aria, node, role, context, visited)
    end
  end

  defp embedded_widget_value(aria, node, role, references, context, visited) do
    if (context.label || context.labelled_by || context.target == :descendant) && node.id not in references do
      widget_value(aria, node, role, context, visited)
    end
  end

  defp widget_value(aria, node, role, _context, visited) when role in ["textbox", "searchbox"] do
    text = if node.tag == "input", do: text_attribute(node, "value"), else: text_content(aria, node)
    {text, visited}
  end

  defp widget_value(aria, node, role, context, visited) when role in ["combobox", "listbox"] do
    case selected_options(aria, node, role) do
      [] when node.tag == "input" ->
        {text_attribute(node, "value"), visited}

      options ->
        {parts, visited} =
          alternatives(aria, Enum.map(options, & &1.id), fn _option -> child_context(context) end, visited)

        {Enum.join(parts, " "), visited}
    end
  end

  defp widget_value(_aria, node, role, _context, visited)
       when role in ["progressbar", "scrollbar", "slider", "spinbutton", "meter"] do
    name = Enum.find(["aria-valuetext", "aria-valuenow"], "value", &attribute?(node, &1))
    {text_attribute(node, name), visited}
  end

  defp widget_value(_aria, _node, "menu", _context, visited), do: {"", visited}
  defp widget_value(_aria, _node, _role, _context, _visited), do: nil

  defp selected_options(aria, %{tag: "select"} = select, _role) do
    options = select_options(aria, select)
    selected = Enum.filter(options, &attribute?(&1, "selected"))

    cond_result =
      cond do
        attribute?(select, "multiple") -> selected
        selected != [] -> [List.last(selected)]
        list_box?(select) -> []
        true -> options |> Enum.reject(&natively_disabled?(aria, &1)) |> Enum.take(1)
      end

    then(cond_result, fn
      [] -> Enum.take(options, 1)
      chosen -> chosen
    end)
  end

  defp selected_options(aria, node, role) do
    listbox = if role == "combobox", do: aria |> aria_owned(node) |> Enum.find(&(role(aria, &1) == "listbox")), else: node

    if listbox do
      aria
      |> aria_owned(listbox)
      |> Enum.filter(&(String.downcase(text_attribute(&1, "aria-selected")) == "true" and role(aria, &1) == "option"))
    else
      []
    end
  end

  defp select_options(aria, select) do
    aria
    |> child_elements(select)
    |> Enum.flat_map(fn
      %{tag: "option"} = option -> [option]
      %{tag: "optgroup"} = group -> aria |> child_elements(group) |> Enum.filter(&(&1.tag == "option"))
      _other -> []
    end)
  end

  defp aria_owned(aria, node) do
    owned =
      aria |> references(node, "aria-owns") |> Enum.flat_map(&[fetch(aria, &1) | descendants(aria, fetch(aria, &1))])

    descendants(aria, node) ++ owned
  end

  defp aria_label(node, visited) do
    label = text_attribute(node, "aria-label")
    if not blank?(label), do: {label, visited}
  end

  defp native_name_unless_presentational(_aria, _node, role, _references, _context, _visited)
       when role in @presentation_roles, do: nil

  defp native_name_unless_presentational(aria, node, _role, references, context, visited) do
    native_name(aria, node, references, context, visited)
  end

  defp native_name(aria, %{tag: "input"} = node, references, context, visited) do
    case Semantics.input_type(node) do
      type when type in ["button", "submit", "reset"] -> {button_value(node, type), visited}
      "file" -> labels_or(aria, node, context, "Choose File", visited)
      "image" -> labels_or(aria, node, context, non_blank_attribute(node, ["alt", "title"]) || "Submit", visited)
      _text_like -> control_name(aria, node, references, visited)
    end
  end

  defp native_name(aria, %{tag: tag} = node, [], _context, visited)
       when tag in ["textarea", "select", "meter", "progress"] do
    control_name(aria, node, [], visited)
  end

  defp native_name(aria, %{tag: "button"} = node, [], _context, visited) do
    if labels(aria, node) != [], do: labels_name(aria, node, visited)
  end

  defp native_name(aria, %{tag: "output"} = node, [], _context, visited) do
    if labels(aria, node) == [],
      do: {text_attribute(node, "title"), visited},
      else: labels_name(aria, node, visited)
  end

  defp native_name(aria, %{tag: "fieldset"} = node, [], context, visited) do
    caption_or_title(aria, node, "legend", context, visited)
  end

  defp native_name(aria, %{tag: "figure"} = node, [], context, visited) do
    caption_or_title(aria, node, "figcaption", context, visited)
  end

  defp native_name(_aria, %{tag: tag} = node, _references, _context, visited) when tag in ["img", "area"] do
    {non_blank_attribute(node, ["alt"]) || text_attribute(node, "title"), visited}
  end

  defp native_name(aria, %{tag: "table"} = node, _references, context, visited) do
    case first_child(aria, node, "caption") do
      nil ->
        if text_attribute(node, "summary") != "", do: {attribute(node, "summary"), visited}

      caption ->
        text_alternative(aria, caption, native_context(aria, caption, context), visited)
    end
  end

  defp native_name(aria, node, _references, context, visited) do
    if svg?(aria, node), do: svg_name(aria, node, context, visited)
  end

  defp button_value(node, type) do
    cond do
      not blank?(text_attribute(node, "value")) -> attribute(node, "value")
      type == "submit" -> "Submit"
      type == "reset" -> "Reset"
      true -> text_attribute(node, "title")
    end
  end

  defp labels_or(aria, node, context, fallback, visited) do
    if labels(aria, node) != [] and context.labelled_by == nil,
      do: labels_name(aria, node, visited),
      else: {fallback, visited}
  end

  defp control_name(_aria, _node, [_reference | _references], _visited), do: nil

  defp control_name(aria, node, [], visited) do
    if labels(aria, node) == [] do
      {placeholder_or_title(node), visited}
    else
      labels_name(aria, node, visited)
    end
  end

  defp placeholder_or_title(node) do
    title = text_attribute(node, "title")

    if title != "" or not placeholder_control?(node),
      do: title,
      else: text_attribute(node, "placeholder")
  end

  defp placeholder_control?(%{tag: "textarea"}), do: true

  defp placeholder_control?(%{tag: "input"} = node) do
    Semantics.input_type(node) in ["text", "password", "number", "search", "tel", "email", "url"]
  end

  defp placeholder_control?(_node), do: false

  defp labels(aria, node), do: Map.get(aria.labels, node.id, [])

  defp labels_name(aria, node, visited) do
    {parts, visited} = alternatives(aria, labels(aria, node), &%{@context | label: visibility(aria, &1)}, visited)
    {parts |> Enum.reject(&(&1 == "")) |> Enum.join(" "), visited}
  end

  defp caption_or_title(aria, node, tag, context, visited) do
    case first_child(aria, node, tag) do
      nil -> {text_attribute(node, "title"), visited}
      caption -> text_alternative(aria, caption, native_context(aria, caption, context), visited)
    end
  end

  defp native_context(aria, node, context), do: %{child_context(context) | native: visibility(aria, node)}

  defp child_context(%{target: :self} = context), do: %{context | target: :descendant}
  defp child_context(context), do: context

  defp svg?(aria, node) do
    match?(%{tag: "svg"}, closest(aria, node, &(&1.tag in ["svg", "foreignObject"])))
  end

  defp svg_name(aria, node, context, visited) do
    title = aria |> child_elements(node) |> Enum.find(&(&1.tag == "title" and svg?(aria, &1)))

    cond do
      title -> text_alternative(aria, title, %{child_context(context) | labelled_by: visibility(aria, title)}, visited)
      node.tag == "a" and not blank?(text_attribute(node, "xlink:title")) -> {attribute(node, "xlink:title"), visited}
      true -> nil
    end
  end

  defp content_or_title(aria, node, role, context, visited) do
    {text, visited} =
      if name_from_content?(node, role, context),
        do: inner_text(aria, node, child_context(context), visited),
        else: {"", visited}

    significant = if context.target == :self, do: String.trim(text), else: text
    title = text_attribute(node, "title")

    cond do
      significant != "" -> {text, visited}
      not blank?(title) and (role not in @presentation_roles or node.tag in ["iframe", "frame"]) -> {title, visited}
      true -> {"", visited}
    end
  end

  defp name_from_content?(node, role, context) do
    role in @name_from_content_roles or (context.target == :descendant and role in @name_from_content_descendant_roles) or
      (node.tag == "summary" and role not in @presentation_roles) or
      context.labelled_by != nil or context.label != nil or context.native != nil
  end

  defp inner_text(aria, node, context, visited) do
    {parts, visited} =
      Enum.map_reduce(node.children ++ references(aria, node, "aria-owns"), visited, fn
        text, visited when is_binary(text) -> {rendered_text(node, text, context), visited}
        id, visited -> element_text(aria, fetch(aria, id), context, visited)
      end)

    {Enum.join(parts), visited}
  end

  defp rendered_text(%{tag: "details"} = node, text, context) do
    if attribute?(node, "open") or hidden_reference?(context), do: text, else: ""
  end

  defp rendered_text(_node, text, _context), do: text

  defp element_text(aria, node, context, visited) do
    {text, visited} = text_alternative(aria, node, context, visited)

    if non_inline?(aria, node), do: {" " <> text <> " ", visited}, else: {text, visited}
  end

  defp non_inline?(aria, node) do
    attribute?(node, "hidden") or node.tag in @non_inline_tags or ruby_text?(aria, node)
  end

  # Outside a ruby, rt has no display of its own.
  defp ruby_text?(aria, %{tag: "rt"} = node), do: match?(%{tag: "ruby"}, parent(aria, node))
  defp ruby_text?(_aria, _node), do: false

  defp text_content(aria, node) do
    Enum.map_join(node.children, fn
      text when is_binary(text) -> text
      id -> text_content(aria, fetch(aria, id))
    end)
  end
end
