defmodule Fluffy.Driver.External.State do
  @moduledoc false

  # `conn` is the off-origin redirect, the page's before a link click, or nil
  # after a LiveView redirect.
  defstruct [:conn]

  @type t :: %__MODULE__{conn: Plug.Conn.t() | nil}
end
