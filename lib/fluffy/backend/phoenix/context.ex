defmodule Fluffy.Backend.Phoenix.Context do
  @moduledoc false

  @enforce_keys [:http, :timeout]
  defstruct [:http, :timeout]

  @type t :: %__MODULE__{
          http: Fluffy.Backend.Phoenix.HTTP.Client.t() | nil,
          timeout: pos_integer()
        }
end
