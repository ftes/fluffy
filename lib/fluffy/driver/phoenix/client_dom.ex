defmodule Fluffy.Driver.Phoenix.ClientDOM do
  @moduledoc false

  import Fluffy.Driver.Phoenix.HTML.Semantics, only: [attribute: 2, has_attribute?: 2, present_attribute?: 2]

  alias Fluffy.Driver.Phoenix.Actionability
  alias Fluffy.Driver.Phoenix.ClientDOM.Query
  alias Fluffy.Driver.Phoenix.Form
  alias Fluffy.Driver.Phoenix.HTML.Aria
  alias Fluffy.Driver.Phoenix.HTML.DocumentIndex
  alias Fluffy.Driver.Phoenix.HTML.Semantics
  alias Fluffy.Driver.Phoenix.HTML.Serializer
  alias Fluffy.Driver.Phoenix.HTML.Target
  alias Fluffy.Driver.Phoenix.Locator, as: PhoenixLocator
  alias Fluffy.Locator

  # `doctype` is the document's doctype as a browser serializes it, which LazyHTML drops,
  # or nil for a fragment or a document without one.
  @enforce_keys [:document]
  defstruct [:document, :doctype, properties: %{}]

  @opaque t :: %__MODULE__{
            document: term(),
            doctype: String.t() | nil,
            properties: map()
          }

  def from_document(html) when is_binary(html) do
    html |> LazyHTML.from_document() |> new(doctype(html))
  end

  def from_document(%LazyHTML{} = document, doctype), do: new(document, doctype)

  defp new(document, doctype) do
    index = index(%__MODULE__{document: document})

    %__MODULE__{
      document: document,
      doctype: doctype,
      properties: enforce_radio_group_exclusivity(%{}, index, MapSet.new())
    }
  end

  # The doctype before the first element, as `XMLSerializer` writes it, by its name only.
  defp doctype(html) do
    case Regex.run(~r/\A\x{FEFF}?(?:\s|<!--.*?-->)*<!doctype\s+([^\s>]+)/isu, html) do
      [_match, name] -> "<!DOCTYPE #{String.downcase(name)}>"
      nil -> nil
    end
  end

  @doc false
  @spec index(%__MODULE__{}) :: DocumentIndex.t()
  def index(%__MODULE__{document: document}), do: Aria.for_document(document).index

  def reconcile(%__MODULE__{} = client_dom, html) when is_binary(html) do
    reconcile(client_dom, LazyHTML.from_fragment(html))
  end

  def reconcile(%__MODULE__{} = client_dom, %LazyHTML{} = new_document) do
    old_nodes = index(client_dom).entries
    new_index = index(%__MODULE__{document: new_document})
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
    old_renders = owner_renders(client_dom.document)
    new_renders = owner_renders(new_document)

    {properties, locally_checked} =
      Enum.reduce(client_dom.properties, {%{}, MapSet.new()}, fn
        {old_id, old_properties}, {properties, locally_checked} ->
          with new_id when not is_nil(new_id) <- Map.get(old_to_new, old_id),
               old when not is_nil(old) <- Map.get(old_by_id, old_id),
               new when not is_nil(new) <- Map.get(new_by_id, new_id),
               reconciled when map_size(reconciled) > 0 <-
                 reconcile_properties(
                   old_properties,
                   old,
                   new,
                   old_to_new,
                   patched?(old_renders, new_renders, owner_of(new_index, new.id)) and
                     not triggered_form_control?(new, new_index) and not ignored?(new_index, new.id)
                 ) do
            locally_checked =
              if Map.get(reconciled, :checked) == true,
                do: MapSet.put(locally_checked, new_id),
                else: locally_checked

            {Map.put(properties, new_id, reconciled), locally_checked}
          else
            _discarded -> {properties, locally_checked}
          end
      end)

    %{
      client_dom
      | document: new_document,
        properties: enforce_radio_group_exclusivity(properties, new_index, locally_checked)
    }
  end

  def click(%__MODULE__{} = client_dom, %Locator{} = locator, driver \\ :static) do
    target = target!(client_dom, locator)

    if target_disabled?(client_dom, follow_label(client_dom, target)) do
      raise Fluffy.ActionabilityError, action: :click, reason: :disabled, locator: locator
    end

    Actionability.ensure_clickable!(target, :click, locator)

    clicks(client_dom, target, driver)
  end

  # The clicks a click on `target` dispatches, in order, and the last one's
  # default action (see `default_action/4`). Each is `{target, page,
  # clicked_page}`: a click toggles a checkbox or selects a radio, and a
  # label's activation behavior then clicks its control. A Phoenix.HTML link
  # prevents the click's default, so it keeps the page it found, and submits
  # instead (`{:phoenix_html, submission}`). The drivers commit the clicks.
  defp clicks(client_dom, target, driver, clicking \\ []) do
    case phoenix_html_submission(client_dom, target) do
      nil ->
        clicked_dom = maybe_toggle_checked(client_dom, target)
        click = {target, client_dom, clicked_dom}

        case default_action(clicked_dom, target, driver, clicking) do
          {:click, control} ->
            {clicks, default} = clicks(clicked_dom, control, driver, [control.id | clicking])
            {[click | clicks], default}

          default ->
            {[click], default}
        end

      submission ->
        {[{target, client_dom, client_dom}], {:phoenix_html, submission}}
    end
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

  @doc false
  def closest(%__MODULE__{} = client_dom, %Target{} = target, fun) do
    case Enum.find([target | Enum.reverse(target.ancestors)], fun) do
      nil -> nil
      element -> inclusive_ancestor(client_dom, target, element)
    end
  end

  defp inclusive_ancestor(_client_dom, %Target{id: id} = target, %{id: id}), do: target
  defp inclusive_ancestor(client_dom, _target, element), do: DocumentIndex.target_by_id(index(client_dom), element.id)

  # A click's default action: `{:link, link}` to follow a link,
  # `{:submit, submitter, submission}` to submit a submit button's form,
  # `{:click, control}` to click a label's control, or nil. `clicking` lists
  # the ids of the controls labels are already clicking in this click.
  defp default_action(client_dom, target, driver, clicking) do
    case activation_target(client_dom, target, clicking) do
      nil ->
        nil

      # A browser dispatches no click to a disabled form control, though the
      # click's enabled check may pass on an enclosing button, as in Playwright.
      {:label, %Target{form_control_disabled?: true}} ->
        nil

      {:label, control} ->
        {:click, control}

      %{tag: tag} = link when tag in ["a", "area"] ->
        {:link, link}

      control ->
        case Form.build(index(client_dom), client_dom.properties, control, driver) do
          nil -> nil
          submission -> {:submit, control, submission}
        end
    end
  end

  # Like a browser's click dispatch, the default action belongs to the closest
  # inclusive ancestor with activation behavior. Actionability already rejects
  # a click inside a disabled control.
  defp activation_target(client_dom, target, clicking) do
    aria = aria(client_dom)

    [target | Enum.reverse(target.ancestors)]
    |> Enum.reduce_while([], fn element, inside ->
      cond do
        activation_behavior?(element) -> {:halt, {:element, element}}
        id = label_control_id(aria, element, inside, clicking) -> {:halt, {:label, id}}
        true -> {:cont, [element | inside]}
      end
    end)
    |> case do
      {:element, element} -> inclusive_ancestor(client_dom, target, element)
      {:label, id} -> {:label, DocumentIndex.target_by_id(index(client_dom), id)}
      _none -> nil
    end
  end

  defp activation_behavior?(%{tag: tag, attributes: attributes}) when tag in ["a", "area"],
    do: has_attribute?(attributes, "href")

  defp activation_behavior?(%{tag: tag}), do: tag in ["button", "input"]

  # HTML's label activation behavior: a label clicks its labelled control,
  # unless the click is on that control or on interactive content in the label.
  # A label without a control has none, so the click goes on to its ancestors.
  # Like Chromium's processing_click_, a label doesn't click a control it is
  # already clicking, so labels that contain each other's control stop.
  defp label_control_id(aria, %{tag: "label"} = label, inside, clicking) do
    id = Aria.label_control_id(aria, label)

    if id && id not in clicking && not Enum.any?(inside, &(&1.id == id or interactive_content?(&1))), do: id
  end

  defp label_control_id(_aria, _element, _inside, _clicking), do: nil

  # Interactive content other than the elements with activation behavior, which
  # take a click before an enclosing label does.
  defp interactive_content?(%{tag: tag}) when tag in ~w(details embed iframe select textarea), do: true

  defp interactive_content?(%{tag: tag, attributes: attributes}) when tag in ~w(audio video),
    do: has_attribute?(attributes, "controls")

  defp interactive_content?(%{tag: "img", attributes: attributes}), do: has_attribute?(attributes, "usemap")
  defp interactive_content?(_element), do: false

  @doc false
  def submit_form(%__MODULE__{} = client_dom, target, driver \\ :static) do
    Form.submit(
      index(client_dom),
      client_dom.properties,
      target,
      driver
    )
  end

  def triggered_submission(%__MODULE__{} = client_dom) do
    Form.triggered(index(client_dom), client_dom.properties)
  end

  def change_event(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = target!(client_dom, locator)
    change_event(client_dom, target)
  end

  def change_event(%__MODULE__{} = client_dom, %Target{} = target) do
    build_change_event(client_dom, index(client_dom), target)
  end

  @doc false
  def dispatch_change_event(%__MODULE__{} = client_dom, target) do
    index = index(client_dom)

    case Form.dispatch_change(index, client_dom.properties, target) do
      nil ->
        nil

      event ->
        event
        |> Map.put(:dispatcher_selector, DocumentIndex.selector_for_id!(index, event.dispatcher_id))
        |> Map.put(:form_selector, DocumentIndex.selector_for_id!(index, event.form_id))
    end
  end

  defp build_change_event(client_dom, index, target) do
    case Form.change(index, client_dom.properties, target) do
      nil ->
        nil

      event ->
        event
        |> Map.put(:dispatcher_selector, DocumentIndex.selector_for_id!(index, event.dispatcher_id))
        |> Map.put(:form_selector, DocumentIndex.selector_for_id!(index, event.form_id))
    end
  end

  def fill(%__MODULE__{} = client_dom, %Locator{} = locator, value, driver, action \\ :fill) when is_binary(value) do
    target = control!(client_dom, locator)
    ensure_target_enabled!(client_dom, target, action, locator)
    ensure_target_editable!(client_dom, target, action, locator)

    if target.tag not in ["input", "textarea"] do
      raise Fluffy.CapabilityError,
        capability: :element_actions,
        operation: action,
        driver: driver,
        detail: "filling contenteditable elements requires a browser"
    end

    properties =
      client_dom.properties
      |> put_property(target.id, :value, value)
      |> put_property(target.id, :used, true)

    {%{client_dom | properties: properties}, target}
  end

  # LiveView marks every element of a submitted form as used, so later change
  # events send no `_unused_` params for them.
  @doc false
  def mark_form_used(%__MODULE__{} = client_dom, form_id) do
    index = index(client_dom)

    properties =
      index
      |> DocumentIndex.targets_by_tag(["button", "input", "select", "textarea"])
      |> Enum.filter(&(Map.get(index.form_owner_ids, &1.id) == form_id))
      |> Enum.reduce(client_dom.properties, &put_property(&2, &1.id, :used, true))

    %{client_dom | properties: properties}
  end

  def set_input_files(%__MODULE__{} = client_dom, %Locator{} = locator, selected_files) when is_list(selected_files) do
    target = control!(client_dom, locator)

    Actionability.ensure_file_input_files!(target, selected_files, :set_input_files, locator)

    %{
      client_dom
      | properties: put_property(client_dom.properties, target.id, :files, selected_files)
    }
  end

  def live_managed_form?(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = control!(client_dom, locator)
    Form.live_managed_form?(index(client_dom), target)
  end

  def live_change_form?(%__MODULE__{} = client_dom, %Locator{} = locator) do
    target = control!(client_dom, locator)
    Form.live_change_form?(index(client_dom), target)
  end

  # Like Playwright's setChecked: nil when the control is already in the
  # state, or else the clicks of a click on the element the locator resolves
  # to, such as the control's label, and the control. The drivers check the
  # control's state once the click took effect (`ensure_checked!/4`).
  def set_checked(%__MODULE__{} = client_dom, %Locator{} = locator, desired, driver \\ :static)
      when is_boolean(desired) do
    target = target!(client_dom, locator)
    control = follow_label(client_dom, target)
    Actionability.ensure_checkable!(control, checked_action(desired), locator)

    cond do
      checked_target?(client_dom, control) == desired ->
        nil

      input_type(control) == "radio" and not desired ->
        raise Fluffy.ActionabilityError,
          action: :uncheck,
          reason: :cannot_uncheck_radio,
          locator: locator

      true ->
        ensure_target_enabled!(client_dom, control, checked_action(desired), locator)
        {clicks(client_dom, target, driver), control}
    end
  end

  # Playwright's setChecked fails when its click left the control's state.
  @doc false
  def ensure_checked!(%__MODULE__{} = client_dom, %Target{} = control, desired, locator) do
    if checked_target?(client_dom, control) != desired do
      raise Fluffy.ActionabilityError, action: checked_action(desired), reason: :state_unchanged, locator: locator
    end
  end

  def select_option(%__MODULE__{} = client_dom, %Locator{} = locator, requested) do
    target = control!(client_dom, locator)
    ensure_target_enabled!(client_dom, target, :select_option, locator)
    Actionability.ensure_selectable!(target, :select_option, locator)

    options = select_options(client_dom, target)
    requested = List.wrap(requested)
    matches = Enum.filter(options, &option_requested?(&1, requested))
    multiple? = has_attribute?(target.attributes, "multiple")
    selected = if multiple?, do: matches, else: Enum.take(matches, 1)

    # An empty list deselects every option, like Playwright's.
    if (selected == [] and requested != []) or (multiple? and not all_options_matched?(requested, matches)) do
      raise Fluffy.ActionabilityError,
        action: :select_option,
        reason: :option_not_found,
        locator: locator
    end

    if Enum.any?(selected, &target_disabled?(client_dom, &1)) do
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

  # Playwright's checked state, which raises for an element without one.
  def checked?(%__MODULE__{} = client_dom, %Locator{} = locator) do
    checked?(client_dom, control!(client_dom, locator), locator)
  end

  def checked?(%__MODULE__{} = client_dom, %Target{} = target, locator) do
    case Aria.checked(aria(client_dom), target, checked_target?(client_dom, target)) do
      :error -> raise Fluffy.ActionabilityError, action: :read_checked, reason: :not_checkbox_or_radio, locator: locator
      checked -> checked
    end
  end

  def value(%__MODULE__{} = client_dom, %Locator{} = locator), do: target_value(client_dom, control!(client_dom, locator))

  # Playwright's inputValue: the value of the control the target retargets to, which
  # must be an input, textarea or select.
  def input_value(%__MODULE__{} = client_dom, %Locator{} = locator) do
    input_value(client_dom, control!(client_dom, locator), locator, :not_input)
  end

  def input_value(%__MODULE__{} = client_dom, %Target{} = target, locator, invalid_reason) do
    if target.tag not in ["input", "textarea", "select"] do
      raise Fluffy.ActionabilityError, action: :input_value, reason: invalid_reason, locator: locator
    end

    target_value(client_dom, target)
  end

  # The DOM's textContent of the one target, or of each match, and getAttribute: they
  # read the element itself, without retargeting.
  def text_content(%__MODULE__{} = client_dom, %Locator{} = locator),
    do: client_dom |> target!(locator) |> Semantics.text_content()

  def all_text_contents(%__MODULE__{} = client_dom, %Locator{} = locator),
    do: client_dom |> targets(locator) |> Enum.map(&Semantics.text_content/1)

  def get_attribute(%__MODULE__{} = client_dom, %Locator{} = locator, name),
    do: client_dom |> target!(locator) |> Semantics.get_attribute(name)

  # Playwright's page.content(): the doctype and the <html> element's outerHTML, without
  # comments around it. A fragment, which has no <html>, is its nodes.
  def content(%__MODULE__{document: document, doctype: doctype}) do
    tree = LazyHTML.to_tree(document)

    case Enum.find(tree, &match?({"html", _attributes, _children}, &1)) do
      nil -> Serializer.to_html(tree)
      html -> (doctype || "") <> Serializer.to_html([html])
    end
  end

  # document.title: the first <title>'s text, its whitespace stripped and collapsed.
  def title(%__MODULE__{document: document}) do
    case document |> LazyHTML.query("title") |> Enum.at(0) do
      nil -> ""
      title -> title |> LazyHTML.text() |> Semantics.collapse_whitespace()
    end
  end

  # Playwright's locator.waitFor: strict, it waits for the one match to reach `state`,
  # or, for `:detached` and `:hidden`, for none.
  def wait_for(%__MODULE__{} = client_dom, %Locator{} = locator, state) do
    case resolve(client_dom, locator) do
      [] when state in [:detached, :hidden] ->
        :ok

      [element] ->
        visible? = PhoenixLocator.structurally_visible?(aria(client_dom), element)

        case {state, visible?} do
          {:attached, _visible?} ->
            :ok

          {:visible, true} ->
            :ok

          {:hidden, false} ->
            :ok

          {:detached, _visible?} ->
            raise Fluffy.ActionabilityError, action: :wait_for, reason: :attached, locator: locator

          {:visible, false} ->
            raise Fluffy.ActionabilityError, action: :wait_for, reason: :hidden, locator: locator

          {:hidden, true} ->
            raise Fluffy.ActionabilityError, action: :wait_for, reason: :visible, locator: locator
        end

      candidates ->
        raise Fluffy.StrictnessError, locator: locator, candidates: candidates
    end
  end

  @doc false
  def target_value(client_dom, target) do
    if target.tag == "select" do
      client_dom |> selected_values_for_target(target) |> List.first() || ""
    else
      client_dom.properties
      |> Map.get(target.id, %{})
      |> Map.get(:value, default_value(target))
    end
  end

  # As in Playwright, only a multiple select has values, enabled or not.
  def selected_values(%__MODULE__{} = client_dom, %Target{} = target, locator) do
    if target.tag != "select" or not has_attribute?(target.attributes, "multiple") do
      raise Fluffy.ActionabilityError, action: :read_value, reason: :not_multiple_select, locator: locator
    end

    selected_values_for_target(client_dom, target)
  end

  @doc false
  def target_disabled?(client_dom, target), do: Aria.aria_disabled?(aria(client_dom), target)

  defp aria(client_dom), do: Aria.for_document(client_dom.document)

  # Playwright's retarget(..., "follow-label"), which fill, clear, select_option,
  # set_input_files, set_checked, the value and the enabled, checked and editable
  # states use, as does click's enabled check. An element other than a form
  # control first goes to the closest button, so text inside a disabled button
  # is disabled, and an element in a label then acts as its control.
  @doc false
  def control!(%__MODULE__{} = client_dom, locator), do: follow_label(client_dom, target!(client_dom, locator))

  @no_follow_label_tags ~w(a input textarea button select option optgroup)

  @doc false
  def follow_label(client_dom, target) do
    aria = aria(client_dom)

    target =
      if target.tag in ["input", "textarea", "select"] or Aria.content_editable?(aria, target) do
        target
      else
        closest(client_dom, target, fn %{tag: tag, attributes: attributes} ->
          tag == "button" or attribute(attributes, "role") in ["button", "checkbox", "radio"]
        end) || target
      end

    with false <-
           target.tag in @no_follow_label_tags or
             attribute(target.attributes, "role") in ["link", "button", "checkbox", "radio"] or
             Aria.content_editable?(aria, target),
         %Target{} = label <- closest(client_dom, target, &(&1.tag == "label")),
         id when is_integer(id) <- Aria.label_control_id(aria, label) do
      DocumentIndex.target_by_id(index(client_dom), id)
    else
      _no_control -> target
    end
  end

  # Playwright's editable state, which raises for an element without a readonly state.
  @doc false
  def editable?(%__MODULE__{} = client_dom, %Target{} = target, locator) do
    case Aria.readonly(aria(client_dom), target) do
      :error -> raise Fluffy.ActionabilityError, action: :read_editable, reason: :no_readonly_state, locator: locator
      readonly -> not readonly and not target_disabled?(client_dom, target)
    end
  end

  @doc false
  def resolve(%__MODULE__{} = client_dom, %Locator{} = locator) do
    Query.resolve(client_dom.document, locator, fn -> checked_ids(client_dom) end)
  end

  defp checked_ids(client_dom) do
    client_dom
    |> index()
    |> DocumentIndex.targets_by_tag(["input", "select"])
    |> Enum.flat_map(fn
      %{tag: "select"} = target ->
        client_dom |> selected_options_for_target(target) |> Enum.map(& &1.id)

      target ->
        if input_type(target) in ["checkbox", "radio"] and checked_target?(client_dom, target),
          do: [target.id],
          else: []
    end)
    |> MapSet.new()
  end

  @doc false
  def target!(%__MODULE__{} = client_dom, locator) do
    elements = resolve(client_dom, locator)

    case elements do
      [_element] -> client_dom |> targets(locator, elements) |> List.first()
      candidates -> raise Fluffy.StrictnessError, locator: locator, candidates: candidates
    end
  end

  @doc false
  def targets(%__MODULE__{} = client_dom, %Locator{} = locator) do
    elements = resolve(client_dom, locator)
    targets(client_dom, locator, elements)
  end

  defp targets(client_dom, _locator, elements) do
    Enum.map(elements, &DocumentIndex.target!(index(client_dom), &1))
  end

  @doc false
  def selector_for_node_id(%__MODULE__{} = client_dom, node_id) do
    DocumentIndex.selector_for_id!(index(client_dom), node_id)
  end

  defp maybe_toggle_checked(client_dom, target) do
    case input_type(target) do
      "checkbox" ->
        put_checked(client_dom, target.id, not checked_target?(client_dom, target))

      # A click on a selected radio changes nothing, like a browser's.
      "radio" ->
        if checked_target?(client_dom, target),
          do: client_dom,
          else: client_dom |> clear_radio_group(target) |> put_checked(target.id, true)

      _other ->
        client_dom
    end
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

  defp clear_radio_group(client_dom, %{attributes: attributes, id: target_id}) do
    case attribute(attributes, "name") do
      name when name in [nil, ""] ->
        client_dom

      name ->
        index = index(client_dom)
        target_owner_id = Map.get(index.form_owner_ids, target_id)

        index
        |> DocumentIndex.targets_by_tag("input")
        |> Enum.reduce(client_dom, fn radio, dom ->
          case {input_type(radio), attribute(radio.attributes, "name"), radio.id, Map.get(index.form_owner_ids, radio.id)} do
            # Only the activated radio becomes used, as in LiveView. Marking the
            # rest would shift `used` onto other controls after a patch.
            {"radio", ^name, id, ^target_owner_id} when id != target_id ->
              %{dom | properties: put_property(dom.properties, id, :checked, false)}

            _other ->
              dom
          end
        end)
    end
  end

  defp input_type(target), do: Semantics.input_type(target)

  # A radio group has at most one checked radio. When reconciliation leaves
  # several, the server's rendering wins over preserved local checkedness,
  # mirroring a browser where setting one radio checked clears its group.
  defp enforce_radio_group_exclusivity(properties, index, locally_checked) do
    index
    |> DocumentIndex.targets_by_tag("input")
    |> Enum.filter(fn target ->
      input_type(target) == "radio" and attribute(target.attributes, "name") not in [nil, ""] and
        properties |> Map.get(target.id, %{}) |> Map.get(:checked, has_attribute?(target.attributes, "checked"))
    end)
    |> Enum.group_by(&{Map.get(index.form_owner_ids, &1.id), attribute(&1.attributes, "name")}, & &1.id)
    |> Enum.reduce(properties, fn
      {_group, [_single]}, properties ->
        properties

      {_group, checked_ids}, properties ->
        winner = checked_ids |> Enum.reject(&MapSet.member?(locally_checked, &1)) |> List.last() || List.last(checked_ids)

        checked_ids
        |> List.delete(winner)
        |> Enum.reduce(properties, &put_property(&2, &1, :checked, false))
    end)
  end

  # Elements without an id are matched by position, so a patch that inserts a
  # sibling can pair an old control with a different new one. Local control
  # state only belongs to the same control: tag, type and name, plus value for
  # checkboxes and radios.
  defp same_control?(old, new), do: control_signature(old) == control_signature(new)

  defp control_signature(%{tag: tag, attributes: attributes} = node) do
    type = input_type(node)
    value = if type in ["checkbox", "radio"], do: attribute(attributes, "value")
    {tag, type, attribute(attributes, "name"), value}
  end

  defp default_value(%{tag: "textarea", children: children}), do: tree_text(children)
  # HTML's default/on value mode: a checkbox or radio without a value is "on", checked or not.
  defp default_value(%{tag: "input"} = target) do
    default = if Semantics.input_type(target) in ["checkbox", "radio"], do: "on", else: ""
    attribute(target.attributes, "value") || default
  end

  defp default_value(%{attributes: attributes}), do: attribute(attributes, "value") || ""

  defp select_options(client_dom, target) do
    client_dom
    |> index()
    |> DocumentIndex.descendants_by_tag(target.id, "option")
    |> Enum.map(&select_option(&1, index(client_dom)))
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
      disabled?: Aria.option_disabled?(index, target)
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
    client_dom |> selected_options_for_target(target) |> Enum.map(& &1.value)
  end

  defp selected_options_for_target(client_dom, target) do
    options = select_options(client_dom, target)

    selected_ids =
      case get_in(client_dom.properties, [target.id, :selected_ids]) do
        nil -> Semantics.default_selected_ids(options, target.attributes)
        ids -> ids
      end

    Enum.filter(options, &(&1.id in selected_ids))
  end

  defp tree_text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &tree_text/1)
  defp tree_text({_tag, _attributes, children}), do: tree_text(children)
  defp tree_text(text) when is_binary(text), do: text
  defp tree_text(_comment), do: ""

  # LiveView patches each view's container on its own, teleported content with
  # the view or component that owns its portal, and skips the components a patch leaves
  # unchanged. It never patches the root layout around them, <title> included.
  # So a control's local values reset only when its owner renders differently.
  # An owner is `{view_id, cid}`; the root layout is `{nil, nil}`.
  defp patched?(_old_renders, _new_renders, {nil, _cid}), do: false
  defp patched?(old_renders, new_renders, owner), do: Map.get(old_renders, owner) != Map.get(new_renders, owner)

  defp owner_of(_index, nil), do: {nil, nil}

  defp owner_of(index, id) do
    entry = Map.fetch!(index.nodes_by_id, id)
    owner(entry.attributes, owner_of(index, portal_id(index, entry.attributes) || entry.parent_id))
  end

  # Teleported content belongs to the owner of its portal's template, which
  # stays at its source.
  defp portal_id(index, attributes) do
    if source = attribute(attributes, "data-phx-teleported-src") do
      index
      |> DocumentIndex.targets_with_attribute("template", "data-phx-portal")
      |> Enum.find_value(&(attribute(&1.attributes, "id") == source && &1.id))
    end
  end

  defp owner(attributes, {view_id, _cid} = parent) do
    cond do
      has_attribute?(attributes, "data-phx-session") -> {attribute(attributes, "id"), nil}
      cid = attribute(attributes, "data-phx-component") -> {view_id, cid}
      true -> parent
    end
  end

  # Each owner's rendering, with the views and components it renders reduced
  # to a reference. Teleported content counts only in its portal's template.
  defp owner_renders(document) do
    {_layout, renders} = document |> LazyHTML.to_tree() |> owner_renders({nil, nil}, %{})
    renders
  end

  defp owner_renders(nodes, parent, renders) do
    Enum.map_reduce(nodes, renders, fn
      {tag, attributes, children}, renders when is_binary(tag) ->
        if has_attribute?(attributes, "data-phx-teleported") do
          {:teleported, renders}
        else
          owner = owner(attributes, parent)
          {children, renders} = owner_renders(children, owner, renders)
          element = {tag, render_attributes(attributes), children}

          if owner == parent,
            do: {element, renders},
            else: {{:owner, owner}, Map.update(renders, owner, [element], &[element | &1])}
        end

      node, renders ->
        {node, renders}
    end)
  end

  # LiveViewTest regenerates signed child-session tokens when rendering, even
  # when the server sent no DOM changes. They must not reset client input values.
  defp render_attributes(attributes), do: Enum.reject(attributes, fn {name, _value} -> name == "data-phx-session" end)

  # LiveView skips input property updates inside a form that is being handed
  # off to HTTP by phx-trigger-action, preserving the user's current values.
  defp triggered_form_control?(entry, index) do
    case DocumentIndex.form_owner(index, %Target{id: entry.id, attributes: entry.attributes, tag: entry.tag}) do
      nil -> false
      form -> has_attribute?(form.attributes, "phx-trigger-action")
    end
  end

  # LiveView's client leaves an element with phx-update="ignore", and all its
  # content, as the user left it.
  defp ignored?(_index, nil), do: false

  defp ignored?(index, id) do
    entry = Map.fetch!(index.nodes_by_id, id)
    attribute(entry.attributes, "phx-update") == "ignore" or ignored?(index, entry.parent_id)
  end

  # `used`, values and selections deliberately carry by identity alone.
  # LiveView keeps `used` on the DOM element morphdom pairs by position, and
  # morphdom resets an unfocused control's value and selection from the render;
  # a select stays unfocused, as Playwright's select_option does not focus it.
  # LiveView resets checked state from the rendered attribute even when the box
  # has focus. So values, selections and checked state survive only unchanged
  # renders, phx-update="ignore" and phx-trigger-action handoff. A reset value
  # stays the current value, as morphdom sets the value property, so a trigger
  # render that then drops the attribute still submits it. That holds only in
  # HTML's value mode; any other input's value is its attribute. Checked and
  # selected state aren't kept that way: the browser keeps them only for
  # controls the user changed, which would take HTML's dirtiness flags.
  # Checked and file state stand in for subtrees LiveView leaves untouched, so
  # they only carry to the same control.
  defp reconcile_properties(properties, old, new, old_to_new, patched?) do
    %{}
    |> preserve_property(properties, :used, true)
    |> preserve_current_value(properties, new, patched?)
    |> preserve_checkedness(properties, old, new, patched?)
    |> preserve_files(properties, old, new)
    |> preserve_selection(properties, old_to_new, patched?)
  end

  defp preserve_property(reconciled, properties, name, true) do
    case Map.fetch(properties, name) do
      {:ok, value} -> Map.put(reconciled, name, value)
      :error -> reconciled
    end
  end

  defp preserve_current_value(reconciled, properties, new, patched?) do
    case Map.fetch(properties, :value) do
      {:ok, value} ->
        cond do
          not Semantics.value_mode?(new) -> reconciled
          patched? -> Map.put(reconciled, :value, default_value(new))
          true -> Map.put(reconciled, :value, value)
        end

      :error ->
        reconciled
    end
  end

  defp preserve_checkedness(reconciled, properties, old, new, patched?) do
    case Map.fetch(properties, :checked) do
      {:ok, checked?} ->
        if not patched? and same_control?(old, new) and
             has_attribute?(old.attributes, "checked") == has_attribute?(new.attributes, "checked"),
           do: Map.put(reconciled, :checked, checked?),
           else: reconciled

      :error ->
        reconciled
    end
  end

  defp preserve_files(reconciled, properties, old, new) do
    case Map.fetch(properties, :files) do
      {:ok, files} ->
        if input_type(new) == "file" and same_control?(old, new),
          do: Map.put(reconciled, :files, files),
          else: reconciled

      :error ->
        reconciled
    end
  end

  defp preserve_selection(reconciled, properties, old_to_new, patched?) do
    case Map.fetch(properties, :selected_ids) do
      {:ok, selected_ids} when not patched? ->
        Map.put(reconciled, :selected_ids, Enum.flat_map(selected_ids, &List.wrap(Map.get(old_to_new, &1))))

      _reset_or_none ->
        reconciled
    end
  end

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

  # Playwright's editable state, then fill's own check of the element.
  defp ensure_target_editable!(client_dom, target, action, locator) do
    case Aria.readonly(aria(client_dom), target) do
      :error ->
        raise Fluffy.ActionabilityError, action: action, reason: :not_editable, locator: locator

      true ->
        raise Fluffy.ActionabilityError, action: action, reason: :readonly, locator: locator

      false ->
        Actionability.ensure_fillable!(target, Aria.content_editable?(aria(client_dom), target), action, locator)
    end
  end

  defp ensure_target_enabled!(client_dom, target, action, locator) do
    if target_disabled?(client_dom, target) do
      raise Fluffy.ActionabilityError, action: action, reason: :disabled, locator: locator
    end
  end
end
