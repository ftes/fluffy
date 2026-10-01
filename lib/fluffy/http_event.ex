defmodule Fluffy.HTTPEvent do
  @moduledoc """
  Normalized metadata for a browser request or response event.

  Response bodies are intentionally not retained in the initial API. Request
  payloads use Playwright's already-buffered `post_data` metadata. `page` is a
  live page handle when known, or nil (for example, a popup's initial request).
  """

  @enforce_keys [:kind, :method, :url, :headers, :resource_type]
  defstruct [
    :kind,
    :method,
    :url,
    :headers,
    :resource_type,
    :post_data,
    :status,
    :status_text,
    :page
  ]

  @type t :: %__MODULE__{
          kind: :request | :response,
          method: String.t(),
          url: String.t(),
          headers: %{optional(String.t()) => String.t()},
          resource_type: String.t(),
          post_data: String.t() | nil,
          status: non_neg_integer() | nil,
          status_text: String.t() | nil,
          page: Fluffy.Page.t() | nil
        }
end
