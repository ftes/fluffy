defmodule Fluffy.Driver.Phoenix.HTML.Semantics do
  @moduledoc false

  @input_types ~w(
    hidden text search tel url email password date month week time datetime-local
    number range color checkbox radio file submit image reset button
  )

  @labelable_tags ~w(button input meter output progress select textarea)

  def attributes(%{attributes: attributes}), do: attributes

  def input_type(%{tag: "input", attributes: attributes}) do
    type = attributes |> attribute("type") |> Kernel.||("text") |> String.downcase()
    if type in @input_types, do: type, else: "text"
  end

  def input_type(_target), do: nil

  # HTML's value mode, in which a control's value is its own, apart from its
  # value attribute: a textarea and the text-like inputs, which are also the
  # ones Playwright's fill accepts.
  @value_mode_input_types ~w(
    text search tel url email password date month week time datetime-local number range color
  )

  def value_mode?(%{tag: "textarea"}), do: true
  def value_mode?(%{tag: "input"} = target), do: input_type(target) in @value_mode_input_types
  def value_mode?(_target), do: false

  def button_type(%{tag: "button", attributes: attributes}) do
    case attributes |> attribute("type") |> Kernel.||("submit") |> String.downcase() do
      type when type in ["button", "reset", "submit"] -> type
      _invalid -> "submit"
    end
  end

  def button_type(_target), do: nil

  def attribute(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  # The DOM's getAttribute, which lowercases the name on an HTML element; the parser keeps
  # the case of SVG and MathML ones, such as viewBox.
  def get_attribute(%{attributes: attributes}, name) when is_binary(name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> attribute(attributes, String.downcase(name, :ascii))
    end
  end

  def present_attribute?(attributes, name) do
    case attribute(attributes, name) do
      value when is_binary(value) and value != "" -> true
      _missing_or_empty -> false
    end
  end

  def has_attribute?(attributes, name), do: List.keymember?(attributes, name, 0)

  # The text Playwright matches and asserts on. Like textContent, it leaves out a
  # template's content, which is not part of the document.
  def text(%{tag: tag, attributes: attributes, children: children}), do: tree_text({tag, attributes, children})

  defp tree_text({tag, _attributes, _children}) when tag in ~w(script noscript style template), do: ""

  defp tree_text({"input", attributes, _children}) do
    type = String.downcase(attribute(attributes, "type") || "")
    if type in ~w(submit button reset), do: attribute(attributes, "value") || "", else: ""
  end

  defp tree_text({_tag, _attributes, children}), do: Enum.map_join(children, &tree_text/1)
  defp tree_text(text) when is_binary(text), do: text
  defp tree_text(_comment), do: ""

  # The DOM's textContent: every descendant text, hidden and script text included. A
  # template's content is a fragment of its own, outside the element's children.
  def text_content(%{tag: "template"}), do: ""
  def text_content(%{children: children}), do: Enum.map_join(children, &content_text/1)

  defp content_text({"template", _attributes, _children}), do: ""
  defp content_text({_tag, _attributes, children}), do: Enum.map_join(children, &content_text/1)
  defp content_text(text) when is_binary(text), do: text
  defp content_text(_comment), do: ""

  # HTML's "strip and collapse ASCII whitespace", as document.title and
  # option.text apply it.
  def collapse_whitespace(text), do: text |> String.split(~r/[\t\n\f\r ]+/, trim: true) |> Enum.join(" ")

  def labelable?(%{tag: "input"} = target), do: input_type(target) != "hidden"
  def labelable?(%{tag: tag}), do: tag in @labelable_tags

  def list_box?(attributes) do
    has_attribute?(attributes, "multiple") or
      case attributes |> attribute("size") |> Kernel.||("") |> String.trim_leading() |> Integer.parse() do
        {size, _rest} -> size > 1
        :error -> false
      end
  end

  # What a `select` shows before input. Each option needs :id, :attributes and
  # :disabled?, from `Fluffy.Driver.Phoenix.HTML.Aria.option_disabled?/2`.
  def default_selected_ids(options, attributes) do
    selected = options |> Enum.filter(&has_attribute?(&1.attributes, "selected")) |> Enum.map(& &1.id)

    cond do
      selected != [] -> if(has_attribute?(attributes, "multiple"), do: selected, else: Enum.take(selected, -1))
      list_box?(attributes) -> []
      true -> options |> Enum.reject(& &1.disabled?) |> Enum.take(1) |> Enum.map(& &1.id)
    end
  end
end
