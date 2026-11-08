defmodule Fluffy.Driver.Playwright.State do
  @moduledoc false

  # `navigated` is set when the main frame navigates and cleared before Fluffy
  # reads the document it adopts, so a set flag means `document_identity` may
  # be stale.
  @enforce_keys [:page, :frame, :navigated]
  defstruct [:page, :frame, :document_identity, :navigated]

  @type t :: %__MODULE__{
          page: PlaywrightEx.Page.t(),
          frame: PlaywrightEx.Frame.t(),
          document_identity: String.t() | nil,
          navigated: :atomics.atomics_ref()
        }
end
