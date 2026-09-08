defmodule Fluffy.ClientDOM do
  @moduledoc false

  alias Fluffy.Actionability
  alias Fluffy.HTML.DocumentIndex
  alias Fluffy.HTML.Semantics
  alias Fluffy.HTML.Target
  alias Fluffy.Locator
  alias Fluffy.Locator.Static, as: StaticLocator

  @enforce_keys [:document, :index]
  defstruct [:document, :index, focused: nil, properties: %{}]

  @opaque t :: %__MODULE__{
            document: term(),
            index: DocumentIndex.t(),
            focused: integer() | nil,
            properties: map()
          }

  def from_fragment(html) when is_binary(html) do
    html |> LazyHTML.from_fragment() |> new()
  end

  def from_document(html) when is_binary(html) do
    html |> LazyHTML.from_document() |> new()
  end

  defp new(document) do
    index = DocumentIndex.new(document)

    %__MODULE__{
      document: document,
      index: index,
      properties: initial_radio_properties(index)
    }
  end

  def reconcile(%__MODULE__{} = client_dom, html) when is_binary(html) do
    new_document = LazyHTML.from_fragment(html)
    new_index = DocumentIndex.new(new_document)
    old_nodes = client_dom.index.entries
    new_nodes = new_index.entries
    new_by_identity = Map.new(new_nodes, &{&1.identity, &1})

    old_to_new =
      old_nodes
      |> Enum.flat_map(fn old ->
        case Map.get(new_by_identity, old.identity) do
          nil -> []
          new -> [{old.id, new.id}]
        end
      end)
      |> Map.new()

    old_by_id = Map.new(old_nodes, &{&1.id, &1})
    new_by_id = Map.new(new_nodes, &{&1.id, &1})
    patched? = patch_tree(LazyHTML.to_tree(client_dom.document)) != patch_tree(LazyHTML.to_tree(new_document))

    properties =
      Enum.reduce(client_dom.properties, initial_radio_properties(new_index), fn
        {old_id, old_properties}, properties ->
          with new_id when not is_nil(new_id) <- Map.get(old_to_new, old_id),
               old when not is_nil(old) <- Map.get(old_by_id, old_id),
               new when not is_nil(new) <- Map.get(new_by_id, new_id),
               reconciled when map_size(reconciled) > 0 <-
                 reconcile_properties(
                   old_properties,
                   old,
                   new,
                   old_id == client_dom.focused,
                   old_to_new,
                   patched? and not triggered_form_control?(new, new_index)
                 ) do
            Map.put(properties, new_id, reconciled)
          else
            _discarded -> properties
          end
      end)

    %__MODULE__{
      document: new_document,
      index: new_index,
      focused: Map.get(old_to_new, client_dom.focused),
      properties: properties
    }
  end

  def click(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    ensure_target_enabled!(target, :click, locator)
    Actionability.ensure_clickable!(target.element, :click, locator)

    client_dom =
      client_dom
      |> maybe_focus(target)
      |> maybe_toggle_checked(target)
      |> maybe_reset_form(target)

    {client_dom, target}
  end

  @doc false
  def phoenix_html_submission(%__MODULE__{} = _client_dom, target) do
    target
    |> phoenix_html_action_target()
    |> case do
      nil ->
        nil

      %{attributes: attributes} ->
        method = attribute(attributes, "data-method")

        %{
          action: attribute(attributes, "data-to"),
          enctype: "application/x-www-form-urlencoded",
          fields: [{"_csrf_token", attribute(attributes, "data-csrf") || ""}, {"_method", method}],
          form_id: nil,
          method: if(method == "get", do: :get, else: :post),
          phx_submit?: false
        }
    end
  end

  @doc false
  def phoenix_html_action_target(target) do
    Enum.find([target | Enum.reverse(target.ancestors)], fn candidate ->
      present_attribute?(candidate.attributes, "data-method") and
        present_attribute?(candidate.attributes, "data-to")
    end)
  end

  def form_submission(%__MODULE__{} = client_dom, target, driver \\ :static) do
    Fluffy.Form.build(client_dom.index, client_dom.properties, target, driver)
  end

  @doc false
  def submit_form(%__MODULE__{} = client_dom, target, driver \\ :static) do
    Fluffy.Form.submit(
      client_dom.index,
      client_dom.properties,
      target,
      driver
    )
  end

  @doc false
  def implicit_submission(%__MODULE__{} = client_dom, %Locator{} = locator, driver \\ :static) do
    target = target!(client_dom, locator)

    Fluffy.Form.implicit_submission(
      client_dom.index,
      client_dom.properties,
      target,
      driver
    )
  end

  def triggered_submission(%__MODULE__{} = client_dom) do
    Fluffy.Form.triggered(client_dom.index, client_dom.properties)
  end

  def change_event(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    change_event(client_dom, target)
  end

  def change_event(%__MODULE__{} = client_dom, %Target{} = target) do
    build_change_event(client_dom, client_dom.index, target)
  end

  @doc false
  def dispatch_change_event(%__MODULE__{} = client_dom, target) do
    index = client_dom.index

    case Fluffy.Form.dispatch_change(index, client_dom.properties, target) do
      nil ->
        nil

      event ->
        event
        |> Map.put(:dispatcher_selector, DocumentIndex.selector_for_id!(index, event.dispatcher_id))
        |> Map.put(:form_selector, DocumentIndex.selector_for_id!(index, event.form_id))
    end
  end

  defp build_change_event(client_dom, index, target) do
    case Fluffy.Form.change(index, client_dom.properties, target) do
      nil ->
        nil

      event ->
        event
        |> Map.put(:dispatcher_selector, DocumentIndex.selector_for_id!(index, event.dispatcher_id))
        |> Map.put(:form_selector, DocumentIndex.selector_for_id!(index, event.form_id))
    end
  end

  def fill(%__MODULE__{} = client_dom, %Locator{} = locator, value) when is_binary(value) do
    target = target!(client_dom, locator)
    ensure_target_enabled!(target, :fill, locator)
    Actionability.ensure_editable!(target.element, :fill, locator)

    properties =
      client_dom.properties
      |> put_property(target.id, :value, value)
      |> put_property(target.id, :used, true)

    {%{client_dom | focused: target.id, properties: properties}, target}
  end

  def set_input_files(%__MODULE__{} = client_dom, %Locator{} = locator, selected_files) when is_list(selected_files) do
    target = target!(client_dom, locator)

    Actionability.ensure_file_input_files!(
      target.element,
      selected_files,
      :set_input_files,
      locator
    )

    %{
      client_dom
      | properties: put_property(client_dom.properties, target.id, :files, selected_files)
    }
  end

  def live_managed_form?(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    Fluffy.Form.live_managed_form?(client_dom.index, target)
  end

  def live_change_form?(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    Fluffy.Form.live_change_form?(client_dom.index, target)
  end

  def set_checked(%__MODULE__{} = client_dom, %Locator{} = locator, desired) when is_boolean(desired) do
    target = target!(client_dom, locator)
    Actionability.ensure_checkable!(target.element, checked_action(desired), locator)
    current = checked_target?(client_dom, target)

    client_dom =
      cond do
        current == desired ->
          client_dom

        input_type(target) == "radio" and not desired ->
          raise Fluffy.ActionabilityError,
            action: :uncheck,
            reason: :cannot_uncheck_radio,
            locator: locator

        true ->
          ensure_target_enabled!(target, checked_action(desired), locator)
          Actionability.ensure_enabled!(target.element, checked_action(desired), locator)

          client_dom
          |> Map.put(:focused, target.id)
          |> put_checked_target(target, desired)
      end

    {client_dom, target}
  end

  def select_option(%__MODULE__{} = client_dom, %Locator{} = locator, requested) do
    target = target!(client_dom, locator)
    ensure_target_enabled!(target, :select_option, locator)
    Actionability.ensure_selectable!(target.element, :select_option, locator)

    options = select_options(client_dom, target)
    requested = List.wrap(requested)
    matches = Enum.filter(options, &option_requested?(&1, requested))
    multiple? = has_attribute?(target.attributes, "multiple")
    selected = if multiple?, do: matches, else: Enum.take(matches, 1)

    if selected == [] or (multiple? and not all_options_matched?(requested, matches)) do
      raise Fluffy.ActionabilityError,
        action: :select_option,
        reason: :option_not_found,
        locator: locator
    end

    if Enum.any?(selected, & &1.disabled?) do
      raise Fluffy.ActionabilityError,
        action: :select_option,
        reason: :disabled_option,
        locator: locator
    end

    selected_ids = Enum.map(selected, & &1.id)

    properties =
      client_dom.properties
      |> put_property(target.id, :selected_ids, selected_ids)
      |> put_property(target.id, :used, true)

    {%{client_dom | properties: properties}, target}
  end

  def focus(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    if focusable?(target), do: %{client_dom | focused: target.id}, else: client_dom
  end

  def blur(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    if client_dom.focused == target.id, do: %{client_dom | focused: nil}, else: client_dom
  end

  def press(%__MODULE__{} = client_dom, %Locator{} = locator, "Space") do
    {client_dom, _target} = click(client_dom, locator)
    client_dom
  end

  def press(%__MODULE__{} = client_dom, %Locator{} = locator, "Tab") do
    target = target!(client_dom, locator)
    client_dom = if focusable?(target), do: %{client_dom | focused: target.id}, else: client_dom
    targets = tabbable_targets(client_dom)

    case Enum.find_index(targets, &(&1.id == target.id)) do
      nil ->
        client_dom

      index ->
        case Enum.at(targets, index + 1) do
          nil -> %{client_dom | focused: nil}
          next -> %{client_dom | focused: next.id}
        end
    end
  end

  def focused?(%__MODULE__{} = client_dom, %Locator{} = locator) do
    client_dom.focused == target!(client_dom, locator).id
  end

  def checked?(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)

    case input_type(target) do
      type when type in ["checkbox", "radio"] ->
        client_dom.properties
        |> Map.get(target.id, %{})
        |> Map.get(:checked, has_attribute?(target.attributes, "checked"))

      _other ->
        false
    end
  end

  def value(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)

    if target.tag == "select" do
      client_dom |> selected_values_for_target(target) |> List.first() || ""
    else
      client_dom.properties
      |> Map.get(target.id, %{})
      |> Map.get(:value, default_value(target))
    end
  end

  def selected_values(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    Actionability.ensure_selectable!(target.element, :read_value, locator)
    selected_values_for_target(client_dom, target)
  end

  @doc false
  def disabled?(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    target.disabled? or Actionability.disabled?(target.element)
  end

  @doc false
  def editable?(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    not target.disabled? and Actionability.editable?(target.element)
  end

  @doc false
  def target!(%__MODULE__{} = client_dom, locator) do
    elements = StaticLocator.resolve(client_dom.document, locator)

    case elements do
      [_element] -> client_dom |> targets(locator, elements) |> List.first()
      candidates -> raise Fluffy.StrictnessError, locator: locator, candidates: candidates
    end
  end

  @doc false
  def targets(%__MODULE__{} = client_dom, %Locator{} = locator) do
    elements = StaticLocator.resolve(client_dom.document, locator)
    targets(client_dom, locator, elements)
  end

  defp targets(client_dom, _locator, elements) do
    Enum.map(elements, &DocumentIndex.target!(client_dom.index, &1))
  end

  @doc false
  def focused_target(%__MODULE__{focused: nil}), do: nil

  def focused_target(%__MODULE__{} = client_dom) do
    DocumentIndex.target_by_id(client_dom.index, client_dom.focused)
  end

  @doc false
  def keyboard_payload(%__MODULE__{} = client_dom, %Target{} = target, key) do
    maybe_put_keyboard_value(%{"key" => key}, client_dom, target)
  end

  @doc false
  def target_identity(%{tag: tag, attributes: attributes, selector: selector}) do
    cond do
      html_id = attribute(attributes, "id") -> {:html_id, tag, html_id}
      phx_id = attribute(attributes, "data-phx-id") -> {:phx_id, tag, phx_id}
      true -> {:selector, selector}
    end
  end

  @doc false
  def target_identity_present?(%__MODULE__{} = _client_dom, {:selector, _selector}), do: false

  def target_identity_present?(%__MODULE__{} = client_dom, identity) do
    DocumentIndex.identity_present?(client_dom.index, identity)
  end

  @doc false
  def selector_for_node_id(%__MODULE__{} = client_dom, node_id) do
    DocumentIndex.selector_for_id!(client_dom.index, node_id)
  end

  defp maybe_put_keyboard_value(payload, client_dom, target)
       when target.tag in ["button", "input", "option", "output", "select", "textarea"] do
    type = input_type(target)

    if type in ["checkbox", "radio"] and not checked_for_target?(client_dom, target) do
      payload
    else
      Map.put(payload, "value", value_for_target(client_dom, target))
    end
  end

  defp maybe_put_keyboard_value(payload, _client_dom, _target), do: payload

  defp checked_for_target?(client_dom, target) do
    client_dom.properties
    |> Map.get(target.id, %{})
    |> Map.get(:checked, has_attribute?(target.attributes, "checked"))
  end

  defp value_for_target(client_dom, %{tag: "select"} = target) do
    client_dom |> selected_values_for_target(target) |> List.first() || ""
  end

  defp value_for_target(client_dom, target) do
    client_dom.properties
    |> Map.get(target.id, %{})
    |> Map.get(:value, default_value(target))
  end

  defp maybe_focus(client_dom, target) do
    if focusable?(target), do: %{client_dom | focused: target.id}, else: client_dom
  end

  defp focusable?(%{disabled?: true}), do: false

  defp focusable?(%{tag: tag, attributes: attributes}) do
    element_focusable? =
      tag in ["button", "select", "textarea"] or
        (tag == "input" and attribute(attributes, "type") != "hidden") or
        (tag in ["a", "area"] and has_attribute?(attributes, "href")) or
        has_attribute?(attributes, "tabindex")

    element_focusable? and not has_attribute?(attributes, "disabled")
  end

  defp tabbable_targets(client_dom) do
    client_dom.index
    |> DocumentIndex.all_targets()
    |> Enum.with_index()
    |> Enum.flat_map(fn {target, document_index} ->
      tab_index = tab_index(target.attributes)

      if focusable?(target) and tab_index >= 0,
        do: [{target, tab_index, document_index}],
        else: []
    end)
    |> Enum.sort_by(fn {_target, tab_index, document_index} ->
      if tab_index > 0, do: {0, tab_index, document_index}, else: {1, 0, document_index}
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp tab_index(attributes) do
    case Integer.parse(attribute(attributes, "tabindex") || "0") do
      {tab_index, ""} -> tab_index
      _invalid -> 0
    end
  end

  defp maybe_toggle_checked(client_dom, target) do
    case input_type(target) do
      "checkbox" ->
        put_checked(client_dom, target.id, not checked_target?(client_dom, target))

      "radio" ->
        put_checked_target(client_dom, target, true)

      _other ->
        client_dom
    end
  end

  defp maybe_reset_form(client_dom, target) do
    properties = Fluffy.Form.reset(client_dom.index, client_dom.properties, target)
    %{client_dom | properties: properties}
  end

  defp checked_target?(client_dom, target) do
    client_dom.properties
    |> Map.get(target.id, %{})
    |> Map.get(:checked, has_attribute?(target.attributes, "checked"))
  end

  defp put_checked(client_dom, id, checked?) do
    properties =
      client_dom.properties
      |> put_property(id, :checked, checked?)
      |> put_property(id, :used, true)

    %{client_dom | properties: properties}
  end

  defp put_checked_target(client_dom, target, true) do
    if input_type(target) == "radio" do
      client_dom
      |> clear_radio_group(target)
      |> put_checked(target.id, true)
    else
      put_checked(client_dom, target.id, true)
    end
  end

  defp put_checked_target(client_dom, target, false) do
    put_checked(client_dom, target.id, false)
  end

  defp clear_radio_group(client_dom, %{attributes: attributes, id: target_id}) do
    case attribute(attributes, "name") do
      name when name in [nil, ""] ->
        client_dom

      name ->
        index = client_dom.index
        target_owner_id = Map.get(index.form_owner_ids, target_id)

        index
        |> DocumentIndex.targets_by_tag("input")
        |> Enum.reduce(client_dom, fn radio, dom ->
          case {input_type(radio), attribute(radio.attributes, "name"), radio.id, Map.get(index.form_owner_ids, radio.id)} do
            {"radio", ^name, id, ^target_owner_id} when id != target_id ->
              put_checked(dom, id, false)

            _other ->
              dom
          end
        end)
    end
  end

  defp input_type(target), do: Semantics.input_type(target)

  defp initial_radio_properties(index) do
    {properties, _last_checked} =
      index
      |> DocumentIndex.targets_by_tag("input")
      |> Enum.reduce({%{}, %{}}, fn target, {properties, last_checked} ->
        name = attribute(target.attributes, "name")

        if input_type(target) == "radio" and name not in [nil, ""] and
             has_attribute?(target.attributes, "checked") do
          group = {Map.get(index.form_owner_ids, target.id), name}

          properties =
            case Map.get(last_checked, group) do
              nil -> properties
              prior_id -> put_property(properties, prior_id, :checked, false)
            end

          {
            put_property(properties, target.id, :checked, true),
            Map.put(last_checked, group, target.id)
          }
        else
          {properties, last_checked}
        end
      end)

    properties
  end

  defp default_value(%{tag: "textarea", children: children}), do: tree_text(children)
  defp default_value(%{attributes: attributes}), do: attribute(attributes, "value") || ""

  defp select_options(client_dom, target) do
    client_dom.index
    |> DocumentIndex.descendants_by_tag(target.id, "option")
    |> Enum.map(&select_option(&1, client_dom.index))
    |> Enum.with_index()
    |> Enum.map(fn {option, index} -> Map.put(option, :index, index) end)
  end

  defp select_option(target, index) do
    text = target.children |> tree_text() |> normalize_text()

    %{
      id: target.id,
      value: attribute(target.attributes, "value") || text,
      label: attribute(target.attributes, "label") || text,
      attributes: target.attributes,
      disabled?:
        target.disabled? or has_attribute?(target.attributes, "disabled") or
          DocumentIndex.ancestor_has_attribute?(index, target.id, "optgroup", "disabled")
    }
  end

  defp option_requested?(option, requested) do
    Enum.any?(requested, &option_matches?(option, &1))
  end

  defp option_matches?(option, requested) when is_binary(requested) do
    option.value == requested or option.label == normalize_text(requested)
  end

  defp option_matches?(option, %{value: value}), do: option.value == value
  defp option_matches?(option, %{label: label}), do: option.label == normalize_text(label)
  defp option_matches?(option, %{index: index}), do: option.index == index

  defp all_options_matched?(requested, matches) do
    Enum.all?(requested, fn option -> Enum.any?(matches, &option_matches?(&1, option)) end)
  end

  defp selected_values_for_target(client_dom, target) do
    options = select_options(client_dom, target)

    selected_ids =
      case get_in(client_dom.properties, [target.id, :selected_ids]) do
        nil -> default_selected_ids(options, target.attributes)
        ids -> ids
      end

    options
    |> Enum.filter(&(&1.id in selected_ids))
    |> Enum.map(& &1.value)
  end

  defp default_selected_ids(options, attributes) do
    multiple? = has_attribute?(attributes, "multiple")

    selected =
      options
      |> Enum.filter(&has_attribute?(&1.attributes, "selected"))
      |> Enum.map(& &1.id)

    cond do
      selected != [] -> if(multiple?, do: selected, else: Enum.take(selected, -1))
      multiple? -> []
      select_size(attributes) > 1 -> []
      options == [] -> []
      true -> options |> Enum.reject(& &1.disabled?) |> Enum.take(1) |> Enum.map(& &1.id)
    end
  end

  defp select_size(attributes) do
    case Integer.parse(attribute(attributes, "size") || "") do
      {size, ""} when size > 0 -> size
      _missing_or_invalid -> 1
    end
  end

  defp tree_text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &tree_text/1)
  defp tree_text({_tag, _attributes, children}), do: tree_text(children)
  defp tree_text(text) when is_binary(text), do: text
  defp tree_text(_comment), do: ""

  # LiveViewTest regenerates signed child-session tokens when rendering, even
  # when the server sent no DOM changes. They must not reset client input values.
  defp patch_tree(nodes) when is_list(nodes), do: Enum.map(nodes, &patch_tree/1)

  defp patch_tree({tag, attributes, children}) do
    attributes = Enum.reject(attributes, fn {name, _value} -> name == "data-phx-session" end)
    {tag, attributes, patch_tree(children)}
  end

  defp patch_tree(node), do: node

  # LiveView skips input property updates inside a form that is being handed
  # off to HTTP by phx-trigger-action, preserving the user's current values.
  defp triggered_form_control?(entry, index) do
    case DocumentIndex.form_owner(index, %Target{id: entry.id, attributes: entry.attributes, tag: entry.tag}) do
      nil -> false
      form -> has_attribute?(form.attributes, "phx-trigger-action")
    end
  end

  defp reconcile_properties(properties, old, new, focused?, old_to_new, patched?) do
    %{}
    |> preserve_property(properties, :used, true)
    |> preserve_current_value(properties, old, focused?, patched?)
    |> preserve_checkedness(properties, old, new)
    |> preserve_files(properties, old, new)
    |> preserve_selection(properties, old, new, old_to_new)
  end

  defp preserve_property(reconciled, properties, name, true) do
    case Map.fetch(properties, name) do
      {:ok, value} -> Map.put(reconciled, name, value)
      :error -> reconciled
    end
  end

  defp preserve_current_value(reconciled, properties, old, focused?, patched?) do
    case Map.fetch(properties, :value) do
      {:ok, value} ->
        if not patched? or focused_text_control?(old, focused?),
          do: Map.put(reconciled, :value, value),
          else: reconciled

      :error ->
        reconciled
    end
  end

  defp preserve_checkedness(reconciled, properties, old, new) do
    case Map.fetch(properties, :checked) do
      {:ok, checked?} ->
        if has_attribute?(old.attributes, "checked") == has_attribute?(new.attributes, "checked"),
          do: Map.put(reconciled, :checked, checked?),
          else: reconciled

      :error ->
        reconciled
    end
  end

  defp preserve_files(reconciled, properties, old, new) do
    case Map.fetch(properties, :files) do
      {:ok, files} ->
        if file_input?(old) and file_input?(new),
          do: Map.put(reconciled, :files, files),
          else: reconciled

      :error ->
        reconciled
    end
  end

  defp preserve_selection(reconciled, properties, old, new, old_to_new) do
    case Map.fetch(properties, :selected_ids) do
      {:ok, selected_ids} ->
        if option_signature(old.children) == option_signature(new.children) do
          mapped_ids = Enum.flat_map(selected_ids, &List.wrap(Map.get(old_to_new, &1)))
          Map.put(reconciled, :selected_ids, mapped_ids)
        else
          reconciled
        end

      :error ->
        reconciled
    end
  end

  defp focused_text_control?(%{tag: "textarea"}, true), do: true

  defp focused_text_control?(%{tag: "input", attributes: attributes}, true) do
    input_type = attributes |> attribute("type") |> Kernel.||("text") |> String.downcase()

    input_type not in [
      "button",
      "checkbox",
      "file",
      "hidden",
      "image",
      "radio",
      "reset",
      "submit"
    ]
  end

  defp focused_text_control?(_node, _focused?), do: false

  defp file_input?(%{tag: "input", attributes: attributes}) do
    attributes |> attribute("type") |> Kernel.||("text") |> String.downcase() == "file"
  end

  defp file_input?(_node), do: false

  defp option_signature(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &option_signature/1)

  defp option_signature({"option", attributes, children}) do
    [
      {attribute(attributes, "id"), attribute(attributes, "value"), has_attribute?(attributes, "selected"),
       has_attribute?(attributes, "disabled"), tree_text(children)}
    ]
  end

  defp option_signature({_tag, _attributes, children}), do: option_signature(children)
  defp option_signature(_text), do: []

  defp put_property(properties, id, name, value) do
    Map.update(properties, id, %{name => value}, &Map.put(&1, name, value))
  end

  defp normalize_text(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp checked_action(true), do: :check
  defp checked_action(false), do: :uncheck

  defp ensure_target_enabled!(%{disabled?: true}, action, locator) do
    raise Fluffy.ActionabilityError,
      action: action,
      reason: :disabled,
      locator: locator
  end

  defp ensure_target_enabled!(_target, _action, _locator), do: :ok

  defp attribute(attributes, name), do: Semantics.attribute(attributes, name)

  defp present_attribute?(attributes, name), do: Semantics.present_attribute?(attributes, name)

  defp has_attribute?(attributes, name), do: Semantics.has_attribute?(attributes, name)
end
