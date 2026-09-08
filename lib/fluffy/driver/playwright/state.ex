defmodule Fluffy.Driver.Playwright.State do
  @moduledoc false

  @enforce_keys [:frame_id, :page_id]
  defstruct [:context_id, :document_identity, :frame_id, :navigation_observer, :page_id]

  @type t :: %__MODULE__{
          context_id: String.t() | nil,
          document_identity: number() | nil,
          frame_id: String.t(),
          navigation_observer: Fluffy.Playwright.NavigationObserver.t() | nil,
          page_id: String.t()
        }
end
