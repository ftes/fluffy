defmodule Fluffy.Download do
  @moduledoc """
  A normalized download captured by `Fluffy.wait_for/3,4` with
  `Fluffy.Event.download/2`.

  Construct assertions with `Fluffy.Expect` or `Fluffy.Assert`.
  """

  alias Fluffy.URLMatcher

  @enforce_keys [:filename, :content_type, :bytes, :url]
  defstruct [:filename, :content_type, :bytes, :url]

  @type t :: %__MODULE__{
          filename: String.t(),
          content_type: String.t(),
          bytes: binary(),
          url: String.t()
        }

  @doc false
  def matches?(filename, url, options) do
    filename_matches?(Keyword.get(options, :filename), filename) and
      url_matches?(Keyword.get(options, :url), url)
  end

  defp filename_matches?(nil, _actual), do: true
  defp filename_matches?(%Regex{} = expected, actual), do: Regex.match?(expected, actual)
  defp filename_matches?(expected, actual), do: expected == actual

  defp url_matches?(nil, _actual), do: true
  defp url_matches?(expected, actual), do: URLMatcher.matches?(expected, actual)
end
