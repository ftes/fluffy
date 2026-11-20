defmodule Fluffy.Driver.Playwright.State do
  @moduledoc false

  # `navigated` is set when the main frame navigates and cleared before Fluffy
  # reads the document it adopts, so a set flag means `document_identity` may
  # be stale.
  @enforce_keys [:page, :frame, :navigated]
  defstruct [:page, :frame, :document_identity, :navigated]

  @type t :: %__MODULE__{
          page: Playwright.Page.t(),
          frame: Playwright.Frame.t(),
          document_identity: String.t() | nil,
          navigated: :atomics.atomics_ref()
        }

  # A page's document is unknown until Fluffy reads it.
  def new(browser_page) do
    navigated = :atomics.new(1, [])
    :atomics.put(navigated, 1, 1)
    %__MODULE__{page: browser_page, frame: Playwright.Page.main_frame(browser_page), navigated: navigated}
  end
end
