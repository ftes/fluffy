defmodule Fluffy.PageError do
  @moduledoc """
  An uncaught page exception delivered by `Fluffy.Event.page_error/1`.

  `name`, `message` and `stack` follow the JavaScript `Error`. Page code can throw
  a value that is no `Error`: then `message` renders the value, and `name` and
  `stack` are what the browser reports, often empty strings. `page` is the page
  the error occurred in. `Fluffy.unwrap/2` passes the PlaywrightEx exception.
  """

  @enforce_keys [:name, :message, :stack, :page]
  defstruct [:name, :message, :stack, :page, :native]

  @type t :: %__MODULE__{
          name: String.t(),
          message: String.t(),
          stack: String.t(),
          page: Fluffy.Page.t()
        }
end
