defmodule Fluffy.FileChooser do
  @moduledoc """
  A browser file chooser captured by `Fluffy.Event.file_chooser/2`.

  The value is intentionally opaque. Pass its capture key to
  `Fluffy.set_input_files/4`; `multiple?/1` exposes the one stable chooser
  property that is useful without leaking Playwright handles.
  """

  @enforce_keys [:element_id, :page_id, :multiple?]
  defstruct [:element_id, :page_id, :multiple?]

  @opaque t :: %__MODULE__{
            element_id: String.t(),
            page_id: String.t(),
            multiple?: boolean()
          }

  @doc "Returns whether the chooser accepts more than one file."
  @spec multiple?(t()) :: boolean()
  def multiple?(%__MODULE__{multiple?: multiple?}), do: multiple?
end
