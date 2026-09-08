defmodule Fluffy.Dialog do
  @moduledoc """
  A normalized browser dialog and the action Fluffy took to unblock it.
  """

  @enforce_keys [:type, :message, :default_value]
  defstruct [:type, :message, :default_value, :action, :prompt_text]

  @type dialog_type :: :alert | :beforeunload | :confirm | :prompt | String.t()
  @type action :: :accept | :dismiss | nil

  @type t :: %__MODULE__{
          type: dialog_type(),
          message: String.t(),
          default_value: String.t(),
          action: action(),
          prompt_text: String.t() | nil
        }
end
