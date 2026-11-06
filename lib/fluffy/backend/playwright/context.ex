defmodule Fluffy.Backend.Playwright.Context do
  @moduledoc false

  @enforce_keys [:base_url, :browser_context, :resource_scope, :timeout]
  defstruct [:base_url, :browser_context, :resource_scope, :timeout, :trace]

  @type t :: %__MODULE__{
          base_url: String.t(),
          browser_context: PlaywrightEx.BrowserContext.t(),
          resource_scope: pid() | nil,
          timeout: pos_integer(),
          trace: map() | nil
        }
end
