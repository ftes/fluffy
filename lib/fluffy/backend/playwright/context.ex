defmodule Fluffy.Backend.Playwright.Context do
  @moduledoc false

  # The test's action and navigation timeouts, fixed as the session starts, as Playwright.Test
  # sets them on the test's contexts.
  @enforce_keys [:base_url, :browser_context, :action_timeout, :navigation_timeout]
  defstruct [:base_url, :browser_context, :action_timeout, :navigation_timeout, extra_http_headers: %{}]

  @type t :: %__MODULE__{
          base_url: String.t(),
          browser_context: Playwright.BrowserContext.t(),
          action_timeout: timeout(),
          navigation_timeout: timeout(),
          extra_http_headers: %{String.t() => String.t()}
        }
end
