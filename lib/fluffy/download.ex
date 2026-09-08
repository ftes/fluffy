defmodule Fluffy.Download do
  @moduledoc """
  A normalized download captured by `Fluffy.wait_for/3,4` with
  `Fluffy.Event.download/2`.

  Assertion constructors accept the capture key and return a `Fluffy.Expect`
  value for `Fluffy.expect/2`. Capture waits for the event; assertions inspect
  the retained result. Options follow `Fluffy.Expect`.
  """

  alias Fluffy.Expect
  alias Fluffy.URLMatcher

  @enforce_keys [:filename, :content_type, :bytes, :url]
  defstruct [:filename, :content_type, :bytes, :url]

  @type t :: %__MODULE__{
          filename: String.t(),
          content_type: String.t(),
          bytes: binary(),
          url: String.t()
        }

  @doc group: "Assertions"
  @doc """
  Expects the captured download's suggested filename to equal the supplied value.
  """
  @spec to_have_suggested_filename(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_suggested_filename(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:download, key}, :download_suggested_filename, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured download's content type to equal the supplied value.
  """
  @spec to_have_content_type(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_content_type(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:download, key}, :download_content_type, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the complete downloaded bytes to equal the supplied binary; no text decoding is
  performed.
  """
  @spec to_have_content(term(), binary(), [Expect.option()]) :: Expect.t()
  def to_have_content(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:download, key}, :download_content, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the download size in bytes.
  """
  @spec to_have_size(term(), non_neg_integer(), [Expect.option()]) :: Expect.t()
  def to_have_size(key, expected, options \\ []) when is_integer(expected) and expected >= 0 do
    Expect.new({:download, key}, :download_size, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured download URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Page.to_have_url/2`.
  """
  @spec to_have_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def to_have_url(key, expected, options \\ [])

  def to_have_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:download, key}, :download_url, expected, options)
  end

  def to_have_url(key, components, options) when is_list(components) do
    Expect.new({:download, key}, :download_url, URLMatcher.new!(components), options)
  end
end
