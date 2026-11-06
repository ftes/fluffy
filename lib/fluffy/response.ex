defmodule Fluffy.Response do
  @moduledoc """
  A browser response delivered by `Fluffy.Event.response/1` once its headers
  arrive.

  Fields follow Playwright's `Response` accessors; `request` is the
  `Fluffy.Request` that received it. Bodies are not retained.
  """

  @enforce_keys [:url, :status, :status_text, :headers, :request]
  defstruct [:url, :status, :status_text, :headers, :request, :native]

  @type t :: %__MODULE__{
          url: String.t(),
          status: non_neg_integer(),
          status_text: String.t(),
          headers: %{optional(String.t()) => String.t()},
          request: Fluffy.Request.t(),
          native: PlaywrightEx.Response.t() | nil
        }
end
