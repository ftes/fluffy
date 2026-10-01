defmodule Fluffy.FileChooser do
  @moduledoc """
  A browser file chooser captured by `Fluffy.Event.file_chooser/1`.

  The value is intentionally opaque. Pass it directly to
  `Fluffy.set_input_files/4`; `multiple?/1` exposes the one stable chooser
  property that is useful without leaking Playwright handles.
  """

  @enforce_keys [:element_id, :page, :multiple?]
  defstruct [:element_id, :page, :multiple?]

  @opaque t :: %__MODULE__{
            element_id: String.t(),
            page: Fluffy.Page.t(),
            multiple?: boolean()
          }

  @doc "Returns whether the chooser accepts more than one file."
  @spec multiple?(t()) :: boolean()
  def multiple?(%__MODULE__{multiple?: multiple?}), do: multiple?
end
