defmodule Fluffy.Request do
  @moduledoc """
  A browser request delivered by `Fluffy.Event.request/1`, and as the request of
  a `Fluffy.Response`.

  Fields follow Playwright's `Request` accessors. `headers` has lowercase names.
  `post_data` is the buffered request body, or nil. `page` is the live page
  handle when known, or nil (for example, a popup's initial request).
  """

  @enforce_keys [:url, :method, :headers, :resource_type]
  defstruct [:url, :method, :headers, :resource_type, :post_data, :page, :native]

  @type t :: %__MODULE__{
          url: String.t(),
          method: String.t(),
          headers: %{optional(String.t()) => String.t()},
          resource_type: String.t(),
          post_data: String.t() | nil,
          page: Fluffy.Page.t() | nil,
          native: PlaywrightEx.Request.t() | nil
        }
end
