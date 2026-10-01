defmodule Fluffy.Backend.Phoenix.Context do
  @moduledoc false

  @enforce_keys [
    :http,
    :resource_scope,
    :timeout
  ]
  defstruct [
    :http,
    :resource_scope,
    :timeout
  ]

  @type t :: %__MODULE__{
          http: Fluffy.Backend.Phoenix.HTTP.Client.t() | nil,
          resource_scope: pid() | nil,
          timeout: pos_integer()
        }
end
