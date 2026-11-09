defmodule Fluffy.ConsoleMessage do
  @moduledoc """
  A browser console message delivered by `Fluffy.Event.console/1`.

  Fields follow Playwright's `ConsoleMessage` accessors. `type` is the console
  method, such as `"log"` or `"error"`. `location` is the map of
  `PlaywrightEx.ConsoleMessage.location/1`. `page` is the page that logged it, or
  nil for a service worker. Reach the `PlaywrightEx.ConsoleMessage`, for
  arguments as handles, with `Fluffy.unwrap_and_return/2`.
  """

  @enforce_keys [:type, :text, :location, :timestamp]
  defstruct [:type, :text, :location, :timestamp, :page, :native]

  @type t :: %__MODULE__{
          type: String.t(),
          text: String.t(),
          location: map(),
          timestamp: number(),
          page: Fluffy.Page.t() | nil
        }
end
