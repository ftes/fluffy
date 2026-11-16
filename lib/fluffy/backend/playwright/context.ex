defmodule Fluffy.Backend.Playwright.Context do
  @moduledoc false

  @enforce_keys [:base_url, :browser_context]
  defstruct [:base_url, :browser_context, extra_http_headers: %{}]

  @type t :: %__MODULE__{
          base_url: String.t(),
          browser_context: PlaywrightEx.BrowserContext.t(),
          extra_http_headers: %{String.t() => String.t()}
        }
end
