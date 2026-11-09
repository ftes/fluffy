defmodule Fluffy.Worker do
  @moduledoc """
  A dedicated web worker delivered by `Fluffy.Event.worker/1`.

  `url` follows Playwright's `Worker`; `page` is the page that started it. Reach
  the `PlaywrightEx.Worker`, to evaluate in it, with `Fluffy.unwrap/2`.
  """

  @enforce_keys [:url, :page]
  defstruct [:url, :page, :native]

  @type t :: %__MODULE__{url: String.t(), page: Fluffy.Page.t()}
end
