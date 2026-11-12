defmodule Fluffy.Backend.Phoenix.Context do
  @moduledoc false

  @enforce_keys [:http]
  defstruct [:http]

  @type t :: %__MODULE__{
          http: Fluffy.Backend.Phoenix.HTTP.Client.t() | nil
        }
end
