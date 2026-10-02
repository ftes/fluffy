defmodule Fluffy.Page.State do
  @moduledoc false

  @enforce_keys [:driver, :state]
  defstruct [:id, :driver, :state, :url, :status, :opener, :document_id]

  @type t :: %__MODULE__{
          id: reference() | nil,
          driver: :unvisited | :static | :live | :playwright,
          state:
            Fluffy.Driver.Unvisited.State.t()
            | Fluffy.Driver.Static.State.t()
            | Fluffy.Driver.Live.State.t()
            | Fluffy.Driver.Playwright.State.t(),
          url: String.t() | nil,
          status: non_neg_integer() | nil,
          opener: term() | nil,
          document_id: reference() | {reference(), reference() | nil} | nil
        }
end
