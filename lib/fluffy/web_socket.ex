defmodule Fluffy.WebSocket do
  @moduledoc """
  A WebSocket opened by a page, delivered by `Fluffy.Event.web_socket/1`.

  `url` follows Playwright's `WebSocket`; `page` is the page that opened it. Reach
  the `PlaywrightEx.WebSocket`, to read its state or listen to its frames, with
  `Fluffy.unwrap_and_return/2`.
  """

  @enforce_keys [:url, :page]
  defstruct [:url, :page, :native]

  @type t :: %__MODULE__{url: String.t(), page: Fluffy.Page.t()}
end
