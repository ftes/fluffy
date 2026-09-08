defmodule Fluffy.Backend.Playwright.Context do
  @moduledoc false

  @enforce_keys [
    :base_url,
    :connection,
    :context_id,
    :resource_id,
    :resource_scope,
    :timeout,
    :tracing_id
  ]
  defstruct [
    :base_url,
    :connection,
    :context_id,
    :resource_id,
    :resource_scope,
    :timeout,
    :trace,
    :tracing_id
  ]

  @type t :: %__MODULE__{
          base_url: String.t(),
          connection: GenServer.name(),
          context_id: String.t(),
          resource_id: reference() | nil,
          resource_scope: pid() | nil,
          timeout: pos_integer(),
          trace: map() | nil,
          tracing_id: String.t()
        }
end
