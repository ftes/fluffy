defmodule Fluffy.Form do
  @moduledoc false

  alias Fluffy.CapabilityError
  alias Fluffy.HTML.DocumentIndex
  alias Fluffy.HTML.Semantics
  alias Fluffy.HTML.Target
  alias Fluffy.SelectedFile

  def build(index, properties, submitter, driver \\ :static) do
    if submitter?(submitter) do
      case form_owner(index, submitter) do
        nil -> nil
        form -> submission(index, properties, form, submitter, driver)
      end
    end
  end

  @doc false
  def submit(index, properties, %{tag: "form"} = form, driver) do
    submission(index, properties, form, empty_submitter(), driver)
  end

  def submit(_index, _properties, _target, _driver), do: nil

  @doc false
  def implicit_submission(index, properties, target, driver) do
    with true <- implicit_submission_control?(target),
         form when not is_nil(form) <- form_owner(index, target) do
      ensure_implicit_keyboard_default_supported!(index, form, driver)

      case default_submitter(index, form) do
        nil ->
          if blocking_control_count(index, form) == 1 do
            submission(index, properties, form, empty_submitter(), driver)
          end

        submitter ->
          if disabled_submitter?(index, submitter) do
            nil
          else
            submission(index, properties, form, submitter, driver)
          end
      end
    else
      _not_an_implicit_submission -> nil
    end
  end

  @doc false
  def change(index, properties, target) do
    build_change(index, properties, target, nil)
  end

  @doc false
  def dispatch_change(index, properties, target) do
    build_change(index, properties, target, Map.put(target, :dispatch_change?, true))
  end

  defp build_change(index, properties, target, submitter) do
    with form when not is_nil(form) <- form_owner(index, target),
         {:ok, dispatcher_id, only_name} <- change_dispatcher(form, target) do
      owner_ids = form_owner_ids(index)
      fields = successful_fields(index, properties, form, submitter, :live, owner_ids)
      fields = if only_name, do: Enum.filter(fields, &(elem(&1, 0) == only_name)), else: fields

      %{
        dispatcher_id: dispatcher_id,
        fields: add_unused_fields(fields, index, properties, form, owner_ids),
        form_id: node_id(form),
        target_name: attribute(target.attributes, "name")
      }
    else
      _no_change_binding -> nil
    end
  end

  @doc false
  def triggered(index, properties) do
    case DocumentIndex.targets_with_attribute(index, "form", "phx-trigger-action") do
      [] ->
        nil

      [form] ->
        submitter = trigger_submitter()

        index
        |> submission(properties, form, submitter, :static)
        |> Map.put(:phx_submit?, false)

      forms ->
        # LiveView's DOM patcher keeps replacing its single
        # `externalFormTriggered` reference as it encounters newly-triggered
        # forms, then submits the last one after the patch completes.
        form = List.last(forms)
        submitter = trigger_submitter()

        index
        |> submission(properties, form, submitter, :static)
        |> Map.put(:phx_submit?, false)
    end
  end

  @doc false
  def reset(index, properties, target) do
    if resetter?(target) do
      case form_owner(index, target) do
        nil ->
          properties

        form ->
          owner_ids = form_owner_ids(index)

          controls =
            index
            |> DocumentIndex.targets_by_tag(["button", "input", "select", "textarea"])
            |> Enum.filter(&owned_by_form?(&1, form, owner_ids))

          properties = Enum.reduce(controls, properties, &Map.delete(&2, node_id(&1)))
          restore_default_radio_group_state(controls, properties)
      end
    else
      properties
    end
  end

  @doc false
  def owner_id(index, target) do
    case form_owner(index, target) do
      nil -> nil
      form -> node_id(form)
    end
  end

  @doc false
  def live_managed_form?(index, target) do
    case form_owner(index, target) do
      nil -> false
      form -> attribute(attributes(form), "phx-submit") != nil
    end
  end

  @doc false
  def live_change_form?(index, target) do
    case form_owner(index, target) do
      nil -> false
      form -> attribute(attributes(form), "phx-change") != nil
    end
  end

  @doc false
  def disabled?(index, node_id) do
    MapSet.member?(disabled_control_ids(index), node_id)
  end

  @doc false
  def url_encode(fields) do
    fields
    |> Enum.map(&url_encoded_field/1)
    |> Enum.map_join("&", fn {name, value} ->
      form_url_encode(normalize_line_endings(name)) <>
        "=" <> form_url_encode(normalize_line_endings(value))
    end)
  end

  @doc false
  def multipart_encode(fields, boundary) when is_binary(boundary) do
    fields
    |> Enum.map(&multipart_part(&1, boundary))
    |> Kernel.++(["--", boundary, "--\r\n"])
    |> IO.iodata_to_binary()
  end

  @doc false
  def to_params(fields) do
    fields
    |> Enum.map_join("&", fn {name, value} ->
      URI.encode_www_form(name) <> "=" <> URI.encode_www_form(value)
    end)
    |> Plug.Conn.Query.decode()
  end

  defp submission(index, properties, form, submitter, driver) do
    form_attributes = attributes(form)
    submitter_attributes = submitter.attributes
    method = form_method(submitter_attributes, form_attributes)
    enctype = form_enctype(submitter_attributes, form_attributes)
    phx_submit? = attribute(form_attributes, "phx-submit") != nil
    effective_driver = if driver == :live and phx_submit?, do: :live, else: :static

    owner_ids = form_owner_ids(index)
    ensure_supported_entry_features!(index, properties, form, submitter, effective_driver, owner_ids)

    if method == :dialog do
      raise CapabilityError,
        capability: :form_method,
        driver: effective_driver,
        detail: "dialog-form closure requires a browser dialog model"
    end

    if effective_driver == :static and method == :post and enctype == "text/plain" do
      raise CapabilityError,
        capability: :form_encoding,
        driver: :static,
        detail: "the Static form model does not yet support text/plain submission"
    end

    %{
      action:
        attribute(submitter_attributes, "formaction") || attribute(form_attributes, "action") ||
          "",
      method: method,
      fields: successful_fields(index, properties, form, submitter, effective_driver, owner_ids),
      form_id: node_id(form),
      enctype: enctype,
      phx_submit?: phx_submit?
    }
  end

  defp successful_fields(index, properties, form, submitter, driver, owner_ids) do
    disabled_ids = disabled_control_ids(index)

    index
    |> DocumentIndex.targets_by_tag(["button", "input", "select", "textarea"])
    |> Enum.filter(&owned_by_form?(&1, form, owner_ids))
    |> Enum.flat_map(&control_fields(&1, index, properties, submitter, disabled_ids, driver))
  end

  defp default_submitter(index, form) do
    index
    |> DocumentIndex.targets_by_tag(["button", "input"])
    |> Enum.find(fn candidate ->
      submitter?(candidate) and owned_target_by_form?(candidate, form, index)
    end)
  end

  defp blocking_control_count(index, form) do
    index
    |> DocumentIndex.targets_by_tag("input")
    |> Enum.count(fn candidate ->
      implicit_submission_control?(candidate) and
        owned_target_by_form?(candidate, form, index) and not disabled?(index, candidate.id)
    end)
  end

  defp disabled_submitter?(index, submitter) do
    has_attribute?(submitter.attributes, "disabled") or disabled?(index, submitter.id)
  end

  defp implicit_submission_control?(%{tag: "input"} = target) do
    input_type(target) in [
      "text",
      "search",
      "url",
      "tel",
      "email",
      "password",
      "date",
      "month",
      "week",
      "time",
      "datetime-local",
      "number"
    ]
  end

  defp implicit_submission_control?(_target), do: false

  defp control_fields(target, index, properties, submitter, disabled_ids, driver) do
    name = attribute(target.attributes, "name")

    cond do
      target.tag == "input" and input_type(target) == "image" and
          same_target?(target, submitter) ->
        input_fields(target, properties, submitter, name, driver)

      name in [nil, ""] or has_attribute?(target.attributes, "disabled") or
          target.id in disabled_ids ->
        []

      target.tag == "button" ->
        if same_target?(target, submitter) and
             (button_type(target) == "submit" or Map.get(submitter, :dispatch_change?, false)) do
          [{name, attribute(target.attributes, "value") || ""}]
        else
          []
        end

      target.tag == "textarea" ->
        [{name, current_value(target, properties)}]

      target.tag == "select" ->
        Enum.map(selected_values(target, properties, index), &{name, &1})

      target.tag == "input" ->
        input_fields(target, properties, submitter, name, driver)
    end
  end

  defp input_fields(target, properties, submitter, name, driver) do
    case input_type(target) do
      type when type in ["button", "reset"] ->
        []

      "submit" ->
        if same_target?(target, submitter),
          do: [{name, attribute(target.attributes, "value") || ""}],
          else: []

      "image" ->
        if same_target?(target, submitter) do
          raise CapabilityError,
            capability: :form_submission,
            driver: driver,
            detail: "image submitter coordinates are deferred to the full form model"
        else
          []
        end

      "file" when driver == :static ->
        file_fields(target, properties, name)

      "file" when driver == :live ->
        # LiveView-managed files travel through the upload protocol, not the
        # phx-submit form payload. An empty control after cancellation is not a
        # browser form-entry encoding boundary.
        []

      "file" ->
        raise CapabilityError,
          capability: :form_encoding,
          driver: driver,
          detail: "Live file controls require the browser-owned upload model"

      "hidden" when is_binary(name) ->
        if String.downcase(name) == "_charset_",
          do: [{name, "UTF-8"}],
          else: [{name, current_value(target, properties)}]

      type when type in ["checkbox", "radio"] ->
        if checked?(target, properties) do
          [{name, attribute(target.attributes, "value") || "on"}]
        else
          []
        end

      _textual_or_hidden ->
        [{name, current_value(target, properties)}]
    end
  end

  defp file_fields(target, properties, name) do
    case get_in(properties, [target.id, :files]) do
      files when is_list(files) and files != [] ->
        Enum.map(files, fn %SelectedFile{} = file ->
          {:file, name, file.name, file.content_type, file.bytes}
        end)

      _no_selected_file ->
        [{:file, name, "", "application/octet-stream", ""}]
    end
  end

  defp form_owner(index, submitter), do: DocumentIndex.form_owner(index, submitter)

  defp change_dispatcher(form, target) do
    cond do
      attribute(target.attributes, "phx-change") != nil ->
        {:ok, target.id, attribute(target.attributes, "name")}

      attribute(attributes(form), "phx-change") != nil ->
        {:ok, node_id(form), nil}

      true ->
        :none
    end
  end

  defp add_unused_fields(fields, index, properties, form, owner_ids) do
    if has_attribute?(attributes(form), "phx-no-unused-field") do
      fields
    else
      unused_names = unused_names(index, properties, form, owner_ids)

      Enum.flat_map(fields, fn {name, _value} = field ->
        if MapSet.member?(unused_names, name),
          do: [{prepend_name(name, "_unused_"), ""}, field],
          else: [field]
      end)
    end
  end

  defp unused_names(index, properties, form, owner_ids) do
    index
    |> DocumentIndex.targets_by_tag(["button", "input", "select", "textarea"])
    |> Enum.filter(&owned_by_form?(&1, form, owner_ids))
    |> Enum.reject(fn target ->
      attribute(target.attributes, "name") in [nil, ""] or
        target.tag == "button" or
        input_type(target) in ["button", "reset", "submit", "image"]
    end)
    |> Enum.group_by(&attribute(&1.attributes, "name"))
    |> Enum.reduce(MapSet.new(), fn {name, targets}, names ->
      hidden_only? = Enum.all?(targets, &(input_type(&1) == "hidden"))

      used? =
        Enum.any?(targets, fn target ->
          has_attribute?(target.attributes, "phx-no-unused-field") or
            get_in(properties, [target.id, :used]) == true
        end)

      if hidden_only? or used?, do: names, else: MapSet.put(names, name)
    end)
  end

  defp prepend_name(name, prefix) do
    array? = String.ends_with?(name, "[]")
    base = if array?, do: String.slice(name, 0, byte_size(name) - 2), else: name
    base = Regex.replace(~r/([^\[\]]+)(\]?)$/, base, prefix <> "\\1\\2")
    if array?, do: base <> "[]", else: base
  end

  defp owned_by_form?(control, form, owner_ids), do: Map.get(owner_ids, node_id(control)) == node_id(form)

  defp restore_default_radio_group_state(controls, properties) do
    {properties, _last_checked} =
      Enum.reduce(controls, {properties, %{}}, fn control, {properties, last_checked} ->
        target = control
        name = attribute(target.attributes, "name")

        if input_type(target) == "radio" and name not in [nil, ""] and
             has_attribute?(target.attributes, "checked") do
          properties =
            case Map.get(last_checked, name) do
              nil -> properties
              prior_id -> put_control_property(properties, prior_id, :checked, false)
            end

          {put_control_property(properties, target.id, :checked, true), Map.put(last_checked, name, target.id)}
        else
          {properties, last_checked}
        end
      end)

    properties
  end

  defp put_control_property(properties, id, property, value) do
    Map.update(properties, id, %{property => value}, &Map.put(&1, property, value))
  end

  defp selected_values(target, properties, index) do
    options =
      index
      |> DocumentIndex.descendants_by_tag(target.id, "option")
      |> Enum.map(&option_target(&1, index))

    selected_ids =
      case get_in(properties, [target.id, :selected_ids]) do
        nil -> default_selected_ids(options, target.attributes)
        ids -> ids
      end

    options
    |> Enum.filter(&(&1.id in selected_ids and not &1.disabled?))
    |> Enum.map(& &1.value)
  end

  defp default_selected_ids(options, attributes) do
    multiple? = has_attribute?(attributes, "multiple")
    selected = options |> Enum.filter(& &1.selected?) |> Enum.map(& &1.id)

    cond do
      selected != [] -> if(multiple?, do: selected, else: Enum.take(selected, -1))
      multiple? -> []
      select_size(attributes) > 1 -> []
      options == [] -> []
      true -> options |> Enum.reject(& &1.disabled?) |> Enum.take(1) |> Enum.map(& &1.id)
    end
  end

  defp checked?(target, properties) do
    properties
    |> Map.get(target.id, %{})
    |> Map.get(:checked, has_attribute?(target.attributes, "checked"))
  end

  defp current_value(%{tag: "textarea"} = target, properties) do
    properties |> Map.get(target.id, %{}) |> Map.get(:value, tree_text(target.children))
  end

  defp current_value(target, properties) do
    properties
    |> Map.get(target.id, %{})
    |> Map.get(:value, attribute(target.attributes, "value") || "")
  end

  defp node_id(%Target{id: id}), do: id

  defp attributes(element), do: Semantics.attributes(element)

  defp submitter?(%{tag: "button"} = target), do: button_type(target) == "submit"

  defp submitter?(%{tag: "input"} = target), do: input_type(target) in ["submit", "image"]

  defp submitter?(_target), do: false

  defp resetter?(%{tag: "button"} = target), do: button_type(target) == "reset"
  defp resetter?(%{tag: "input"} = target), do: input_type(target) == "reset"
  defp resetter?(_target), do: false

  defp same_target?(_target, nil), do: false
  defp same_target?(target, submitter), do: not is_nil(submitter.id) and target.id == submitter.id

  defp empty_submitter, do: %Target{attributes: [], id: nil, tag: "button"}

  defp trigger_submitter do
    %Target{attributes: [{"formnovalidate", ""}], id: nil, tag: "button"}
  end

  defp button_type(target), do: Semantics.button_type(target)

  defp input_type(target), do: Semantics.input_type(target)

  defp ensure_supported_entry_features!(index, _properties, form, _submitter, driver, owner_ids) do
    if Enum.any?(["onsubmit", "onformdata"], &has_attribute?(attributes(form), &1)) do
      raise CapabilityError,
        capability: :scripted_form_submission,
        driver: driver,
        detail: "inline submit/formdata handlers require Playwright"
    end

    controls =
      index
      |> DocumentIndex.targets_by_tag(["button", "input", "select", "textarea"])
      |> Enum.filter(&owned_by_form?(&1, form, owner_ids))

    if Enum.any?(controls, &(attribute(&1.attributes, "dirname") not in [nil, ""])) do
      raise CapabilityError,
        capability: :form_directionality,
        driver: driver,
        detail: "dirname submission requires computed element directionality"
    end

    if Enum.any?(controls, fn target ->
         target.tag == "textarea" and
           String.downcase(attribute(target.attributes, "wrap") || "") == "hard"
       end) do
      raise CapabilityError,
        capability: :textarea_hard_wrap,
        driver: driver,
        detail: "textarea wrap=hard submission depends on browser layout and column wrapping"
    end

    unsupported_form_associated =
      index
      |> DocumentIndex.all_targets()
      |> Enum.filter(fn target ->
        (target.tag == "object" or String.contains?(target.tag, "-")) and
          owned_target_by_form?(target, form, index)
      end)

    if unsupported_form_associated != [] do
      raise CapabilityError,
        capability: :form_associated_elements,
        driver: driver,
        detail: "object and form-associated custom element entry construction requires a browser"
    end
  end

  defp ensure_implicit_keyboard_default_supported!(index, form, driver) do
    keyboard_handlers = [
      "onkeydown",
      "onkeypress",
      "onkeyup"
    ]

    has_keyboard_handler? =
      index
      |> DocumentIndex.all_targets()
      |> Enum.any?(fn target ->
        owned_target_by_form?(target, form, index) and
          Enum.any?(keyboard_handlers, &has_attribute?(target.attributes, &1))
      end)

    if has_keyboard_handler? do
      raise CapabilityError,
        capability: :keyboard_default_action,
        driver: driver,
        detail: "implicit Enter submission with inline key handlers requires Playwright"
    end
  end

  defp owned_target_by_form?(target, form, index) do
    case form_owner(index, target) do
      nil -> false
      owner -> node_id(owner) == node_id(form)
    end
  end

  defp disabled_control_ids(index), do: index.disabled_ids

  defp form_owner_ids(index), do: index.form_owner_ids

  defp option_target(target, index) do
    %{
      id: target.id,
      value: attribute(target.attributes, "value") || normalize_option_text(target.children),
      selected?: has_attribute?(target.attributes, "selected"),
      disabled?:
        target.disabled? or has_attribute?(target.attributes, "disabled") or
          DocumentIndex.ancestor_has_attribute?(index, target.id, "optgroup", "disabled")
    }
  end

  defp normalize_option_text(children) do
    children
    |> tree_text()
    |> String.replace(~r/[\t\n\f\r ]+/, " ")
    |> String.trim(" ")
  end

  defp tree_text(nodes) when is_list(nodes), do: Enum.map_join(nodes, &tree_text/1)
  defp tree_text({_tag, _attributes, children}), do: tree_text(children)
  defp tree_text(text) when is_binary(text), do: text
  defp tree_text(_comment), do: ""

  defp select_size(attributes) do
    case Integer.parse(attribute(attributes, "size") || "") do
      {size, ""} when size > 0 -> size
      _missing_or_invalid -> 1
    end
  end

  defp normalize_line_endings(value) do
    value
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.replace("\n", "\r\n")
  end

  defp url_encoded_field({:file, name, filename, _content_type, _bytes}), do: {name, filename}

  defp url_encoded_field({name, value}), do: {name, value}

  defp multipart_part({name, value}, boundary) do
    [
      "--",
      boundary,
      "\r\nContent-Disposition: form-data; name=\"",
      multipart_parameter(name),
      "\"\r\n\r\n",
      normalize_line_endings(value),
      "\r\n"
    ]
  end

  defp multipart_part({:file, name, filename, content_type, bytes}, boundary) do
    [
      "--",
      boundary,
      "\r\nContent-Disposition: form-data; name=\"",
      multipart_parameter(name),
      "\"; filename=\"",
      multipart_parameter(filename),
      "\"\r\nContent-Type: ",
      content_type,
      "\r\n\r\n",
      bytes,
      "\r\n"
    ]
  end

  defp multipart_parameter(value) do
    value
    |> String.replace("\r", "%0D")
    |> String.replace("\n", "%0A")
    |> String.replace("\"", "%22")
  end

  defp form_url_encode(value) do
    for <<byte <- value>>, into: "" do
      cond do
        byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in ~c"*-._" ->
          <<byte>>

        byte == ?\s ->
          "+"

        true ->
          "%" <> Base.encode16(<<byte>>)
      end
    end
  end

  defp form_method(submitter_attributes, form_attributes) do
    method =
      submitter_attributes
      |> attribute("formmethod")
      |> Kernel.||(attribute(form_attributes, "method"))

    case method && String.downcase(method) do
      "post" -> :post
      "dialog" -> :dialog
      _missing_or_invalid -> :get
    end
  end

  defp form_enctype(submitter_attributes, form_attributes) do
    case submitter_attributes
         |> attribute("formenctype")
         |> Kernel.||(attribute(form_attributes, "enctype"))
         |> Kernel.||("application/x-www-form-urlencoded")
         |> String.downcase() do
      enctype
      when enctype in [
             "application/x-www-form-urlencoded",
             "multipart/form-data",
             "text/plain"
           ] ->
        enctype

      _invalid ->
        "application/x-www-form-urlencoded"
    end
  end

  defp attribute(attributes, name), do: Semantics.attribute(attributes, name)

  defp has_attribute?(attributes, name), do: Semantics.has_attribute?(attributes, name)
end
