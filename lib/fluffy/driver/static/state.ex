defmodule Fluffy.Driver.Static.State do
  @moduledoc false

  alias Fluffy.Driver.Phoenix.ClientDOM

  defstruct [:client_dom, :conn]

  @type t :: %__MODULE__{client_dom: ClientDOM.t() | nil, conn: Plug.Conn.t() | nil}
end
