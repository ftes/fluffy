defmodule Fluffy.Playwright.Handle do
  @moduledoc """
  Native identifiers for the active Playwright page.

  `Fluffy.unwrap/2` passes this handle to Playwright callbacks. Supply
  `connection: handle.connection` and `timeout: handle.timeout` when invoking
  PlaywrightEx channel functions so custom Playwright connections and the
  session deadline are respected.

  The handle is an immutable snapshot. Returning a changed handle does not
  change the active Fluffy page.
  """

  @enforce_keys [:context_id, :page_id, :frame_id, :connection, :timeout]
  defstruct [:context_id, :page_id, :frame_id, :connection, :timeout]

  @type t :: %__MODULE__{
          context_id: PlaywrightEx.guid(),
          page_id: PlaywrightEx.guid(),
          frame_id: PlaywrightEx.guid(),
          connection: GenServer.name(),
          timeout: non_neg_integer()
        }
end
