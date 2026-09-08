defmodule Fluffy.Navigation do
  @moduledoc """
  Assertions for navigation results captured by `Fluffy.Event.navigation/2`.

  Pass the capture key as the first argument and execute the returned assertion
  with `Fluffy.expect/2`. Capture waits for the event; assertions inspect its
  retained result. Options follow `Fluffy.Expect`.
  """

  alias Fluffy.Expect
  alias Fluffy.URLMatcher

  @doc group: "Assertions"
  @doc """
  Expects the captured navigation URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Page.to_have_url/2`.
  """
  @spec to_have_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def to_have_url(key, expected, options \\ [])

  def to_have_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:navigation, key}, :navigation_url, expected, options)
  end

  def to_have_url(key, components, options) when is_list(components) do
    Expect.new({:navigation, key}, :navigation_url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured navigation source URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Page.to_have_url/2`.
  """
  @spec to_have_from_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def to_have_from_url(key, expected, options \\ [])

  def to_have_from_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:navigation, key}, :navigation_from_url, expected, options)
  end

  def to_have_from_url(key, components, options) when is_list(components) do
    Expect.new({:navigation, key}, :navigation_from_url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured navigation's status to equal the supplied value.
  """
  @spec to_have_status(term(), integer(), [Expect.option()]) :: Expect.t()
  def to_have_status(key, expected, options \\ []) when is_integer(expected) do
    Expect.new({:navigation, key}, :navigation_status, expected, options)
  end
end
