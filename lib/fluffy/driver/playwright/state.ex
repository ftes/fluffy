defmodule Fluffy.Driver.Playwright.State do
  @moduledoc false

  @enforce_keys [:frame_id, :page_id]
  defstruct [:context_id, :document_identity, :frame_id, :page_id]

  @type t :: %__MODULE__{
          context_id: String.t() | nil,
          document_identity: reference() | nil,
          frame_id: String.t(),
          page_id: String.t()
        }
end
