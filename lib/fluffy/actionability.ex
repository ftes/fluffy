defmodule Fluffy.Actionability do
  @moduledoc false

  @fillable_input_types [
    "color",
    "date",
    "datetime-local",
    "email",
    "month",
    "number",
    "password",
    "range",
    "search",
    "tel",
    "text",
    "time",
    "url",
    "week"
  ]

  def ensure_enabled!(element, action, locator) do
    if disabled?(element) do
      raise Fluffy.ActionabilityError,
        action: action,
        reason: :disabled,
        locator: locator
    end

    :ok
  end

  def ensure_clickable!(element, action, locator) do
    ensure_enabled!(element, action, locator)

    if LazyHTML.attribute(element, "hidden") != [] do
      raise_error(action, :hidden, locator)
    end

    :ok
  end

  def disabled?(element) do
    case LazyHTML.attributes(element) do
      [attributes] ->
        List.keymember?(attributes, "disabled", 0) or
          String.downcase(attribute(attributes, "aria-disabled") || "false") == "true"

      _other ->
        false
    end
  end

  @doc false
  def editable?(element) do
    {tag, attributes} = element_info(element)

    not disabled?(element) and
      (editable_text_control?(tag, attributes) or contenteditable?(attributes))
  end

  def ensure_editable!(element, action, locator) do
    ensure_enabled!(element, action, locator)

    {tag, attributes} = element_info(element)

    cond do
      text_control?(tag, attributes) ->
        if readonly?(attributes), do: raise_error(action, :readonly, locator), else: :ok

      contenteditable?(attributes) ->
        :ok

      true ->
        raise_error(action, :not_editable, locator)
    end
  end

  def ensure_checkable!(element, action, locator) do
    {tag, attributes} = element_info(element)

    if !(tag == "input" and input_type(attributes) in ["checkbox", "radio"]) do
      raise_error(action, :not_checkable, locator)
    end

    :ok
  end

  def ensure_selectable!(element, action, locator) do
    {tag, _attributes} = element_info(element)

    if tag != "select" do
      raise_error(action, :not_selectable, locator)
    end

    ensure_enabled!(element, action, locator)
  end

  def ensure_file_input!(element, action, locator) do
    ensure_file_input_type!(element, action, locator)
    ensure_enabled!(element, action, locator)
  end

  def ensure_file_input_type!(element, action, locator) do
    {tag, attributes} = element_info(element)

    if !(tag == "input" and input_type(attributes) == "file") do
      raise_error(action, :not_file_input, locator)
    end
  end

  def ensure_file_input_files!(element, files, action, locator) when is_list(files) do
    # Playwright's setInputFiles validates the element type and multiplicity,
    # but intentionally does not require the file input to be enabled or
    # visible. Keep the portable action aligned with that contract.
    ensure_file_input_type!(element, action, locator)

    if match?([_, _ | _], files) and LazyHTML.attribute(element, "multiple") == [] do
      raise_error(action, :multiple_files_not_allowed, locator)
    end
  end

  defp element_info(element) do
    case LazyHTML.to_tree(element) do
      [{tag, attributes, _children}] -> {tag, attributes}
      _other -> {nil, []}
    end
  end

  defp readonly?(attributes) do
    List.keymember?(attributes, "readonly", 0)
  end

  defp editable_text_control?(tag, attributes) do
    text_control?(tag, attributes) and not readonly?(attributes)
  end

  defp text_control?("textarea", _attributes), do: true

  defp text_control?("input", attributes), do: input_type(attributes) in @fillable_input_types

  defp text_control?(_tag, _attributes), do: false

  defp contenteditable?(attributes) do
    attributes |> attribute("contenteditable") |> contenteditable_value?()
  end

  defp contenteditable_value?(nil), do: false
  defp contenteditable_value?(""), do: true
  defp contenteditable_value?(value), do: String.downcase(value) in ["true", "plaintext-only"]

  defp input_type(attributes) do
    case attributes |> attribute("type") |> Kernel.||("text") |> String.downcase() do
      type
      when type in [
             "button",
             "checkbox",
             "color",
             "date",
             "datetime-local",
             "email",
             "file",
             "hidden",
             "image",
             "month",
             "number",
             "password",
             "radio",
             "range",
             "reset",
             "search",
             "submit",
             "tel",
             "text",
             "time",
             "url",
             "week"
           ] ->
        type

      _invalid ->
        "text"
    end
  end

  defp raise_error(action, reason, locator) do
    raise Fluffy.ActionabilityError,
      action: action,
      reason: reason,
      locator: locator
  end

  defp attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end
end
