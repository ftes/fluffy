defmodule Fluffy.Backend.Phoenix.Context do
  @moduledoc false

  @enforce_keys [
    :http,
    :resource_id,
    :resource_scope,
    :timeout
  ]
  defstruct [
    :http,
    :resource_id,
    :resource_scope,
    :timeout
  ]

  @type t :: %__MODULE__{
          http: Fluffy.Backend.Phoenix.HTTP.Client.t() | nil,
          resource_id: reference() | nil,
          resource_scope: pid() | nil,
          timeout: pos_integer()
        }
end
