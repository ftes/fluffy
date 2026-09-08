defmodule Fluffy.NavigationEvent do
  @moduledoc """
  The common result of a captured main-page navigation.
  """

  @enforce_keys [:from_url, :url, :status]
  defstruct [:from_url, :url, :status]

  @type t :: %__MODULE__{
          from_url: String.t() | nil,
          url: String.t(),
          status: non_neg_integer() | nil
        }
end
