defmodule Fluffy.Driver.Phoenix.HTML.Target do
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
    disabled?: false,
    form_control_disabled?: false
  ]

  @type t :: %__MODULE__{
          attributes: [{String.t(), String.t()}],
          children: list() | nil,
          element: term() | nil,
          id: integer() | nil,
          tag: String.t(),
          ancestors: [t()] | nil,
          selector: String.t() | nil,
          # Natively disabled, by `Fluffy.Driver.Phoenix.HTML.Aria.natively_disabled?/2`.
          disabled?: boolean(),
          # HTML's disabled form control, by `Fluffy.Driver.Phoenix.HTML.Aria.form_control_disabled?/2`.
          form_control_disabled?: boolean()
        }
end
