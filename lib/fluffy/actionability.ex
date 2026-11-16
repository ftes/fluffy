defmodule Fluffy.Actionability do
  @moduledoc false

  import Fluffy.HTML.Semantics, only: [input_type: 1]

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

  # The enabled check belongs to the click's state target, see `Fluffy.ClientDOM.click/2`.
  def ensure_clickable!(element, action, locator) do
    if LazyHTML.attribute(element, "hidden") != [] do
      raise_error(action, :hidden, locator)
    end

    :ok
  end

  # Fill's own check, after the editable state: an input it can type into, a
  # textarea, or contenteditable.
  def ensure_fillable!(element, content_editable?, action, locator) do
    {tag, attributes} = element_info(element)

    if not text_control?(tag, attributes) and not content_editable? do
      raise_error(action, :not_editable, locator)
    end

    :ok
  end

  def ensure_checkable!(element, action, locator) do
    {tag, attributes} = element_info(element)

    if input_type(%{tag: tag, attributes: attributes}) not in ["checkbox", "radio"] do
      raise_error(action, :not_checkable, locator)
    end

    :ok
  end

  def ensure_selectable!(element, action, locator) do
    {tag, _attributes} = element_info(element)

    if tag != "select" do
      raise_error(action, :not_selectable, locator)
    end

    :ok
  end

  def ensure_file_input_type!(element, action, locator) do
    {tag, attributes} = element_info(element)

    if input_type(%{tag: tag, attributes: attributes}) != "file" do
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

  defp text_control?("textarea", _attributes), do: true

  defp text_control?("input", attributes),
    do: input_type(%{tag: "input", attributes: attributes}) in @fillable_input_types

  defp text_control?(_tag, _attributes), do: false

  defp raise_error(action, reason, locator) do
    raise Fluffy.ActionabilityError,
      action: action,
      reason: reason,
      locator: locator
  end
end
