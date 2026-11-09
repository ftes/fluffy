defmodule Fluffy.HTML.Semantics do
  @moduledoc false

  @input_types ~w(
    hidden text search tel url email password date month week time datetime-local
    number range color checkbox radio file submit image reset button
  )

  def attributes(%{attributes: attributes}), do: attributes

  def input_type(%{tag: "input", attributes: attributes}) do
    type = attributes |> attribute("type") |> Kernel.||("text") |> String.downcase()
    if type in @input_types, do: type, else: "text"
  end

  def input_type(_target), do: nil

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

  def present_attribute?(attributes, name) do
    case attribute(attributes, name) do
      value when is_binary(value) and value != "" -> true
      _missing_or_empty -> false
    end
  end

  def has_attribute?(attributes, name), do: List.keymember?(attributes, name, 0)

  def list_box?(attributes) do
    has_attribute?(attributes, "multiple") or
      case attributes |> attribute("size") |> Kernel.||("") |> String.trim_leading() |> Integer.parse() do
        {size, _rest} -> size > 1
        :error -> false
      end
  end

  # What a `select` shows before input. Each option needs :id, :attributes and :disabled?.
  def default_selected_ids(options, attributes) do
    selected = options |> Enum.filter(&has_attribute?(&1.attributes, "selected")) |> Enum.map(& &1.id)

    cond do
      selected != [] -> if(has_attribute?(attributes, "multiple"), do: selected, else: Enum.take(selected, -1))
      list_box?(attributes) -> []
      true -> options |> Enum.reject(& &1.disabled?) |> Enum.take(1) |> Enum.map(& &1.id)
    end
  end
end
