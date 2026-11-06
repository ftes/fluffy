defmodule Fluffy.Driver.Playwright.State do
  @moduledoc false

  @enforce_keys [:page, :frame]
  defstruct [:page, :frame, :document_identity]

  @type t :: %__MODULE__{
          page: PlaywrightEx.Page.t(),
          frame: PlaywrightEx.Frame.t(),
          document_identity: String.t() | nil
        }
end
