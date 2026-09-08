defmodule Fluffy.HTML.Target do
  @moduledoc false

  @enforce_keys [:attributes, :id, :tag]
  defstruct [
    :attributes,
    :children,
    :element,
    :id,
    :tag,
    :ancestors,
    :selector,
    disabled?: false
  ]

  @type t :: %__MODULE__{
          attributes: [{String.t(), String.t()}],
          children: list() | nil,
          element: term() | nil,
          id: integer() | nil,
          tag: String.t(),
          ancestors: [t()] | nil,
          selector: String.t() | nil,
          disabled?: boolean()
        }
end
