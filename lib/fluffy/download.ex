defmodule Fluffy.Download do
  @moduledoc """
  A normalized download captured by `Fluffy.wait_for/3,4` with
  `Fluffy.Event.download/2`.
  """

  @enforce_keys [:filename, :content_type, :bytes, :url]
  defstruct [:filename, :content_type, :bytes, :url]

  @type t :: %__MODULE__{
          filename: String.t(),
          content_type: String.t(),
          bytes: binary(),
          url: String.t()
        }
end
