defmodule Fluffy.FileChooser do
  @moduledoc """
  A browser file chooser captured by `Fluffy.Event.file_chooser/1`.

  Pass it directly to `Fluffy.set_input_files/4`. `multiple?/1` tells whether
  the chooser accepts more than one file.
  """

  @enforce_keys [:native, :page, :multiple?]
  defstruct [:native, :page, :multiple?]

  @opaque t :: %__MODULE__{
            native: PlaywrightEx.FileChooser.t(),
            page: Fluffy.Page.t(),
            multiple?: boolean()
          }

  @doc "Returns whether the chooser accepts more than one file."
  @spec multiple?(t()) :: boolean()
  def multiple?(%__MODULE__{multiple?: multiple?}), do: multiple?

  @doc "Returns the page the chooser belongs to."
  @spec page(t()) :: Fluffy.Page.t()
  def page(%__MODULE__{page: page}), do: page
end
