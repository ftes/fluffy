defmodule Fluffy.Request do
  @moduledoc """
  Assertions for request results captured by `Fluffy.Event.request/3`.

  Pass the capture key as the first argument and execute the returned assertion
  with `Fluffy.expect/2`. Capture waits for the event; assertions inspect its
  retained result. Options follow `Fluffy.Expect`.
  """

  alias Fluffy.Expect
  alias Fluffy.URLMatcher

  @doc group: "Assertions"
  @doc """
  Expects the captured request's method to equal the supplied value.
  """
  @spec to_have_method(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_method(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:request, key}, :request_method, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Page.to_have_url/2`.
  """
  @spec to_have_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def to_have_url(key, expected, options \\ [])

  def to_have_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:request, key}, :request_url, expected, options)
  end

  def to_have_url(key, components, options) when is_list(components) do
    Expect.new({:request, key}, :request_url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request headers to include every supplied key/value pair. Additional
  headers are allowed.
  """
  @spec to_have_headers(term(), map(), [Expect.option()]) :: Expect.t()
  def to_have_headers(key, expected, options \\ []) when is_map(expected) do
    Expect.new({:request, key}, :request_headers, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request's resource type to equal the supplied value.
  """
  @spec to_have_resource_type(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_resource_type(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:request, key}, :request_resource_type, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request's post data to equal the supplied value.
  """
  @spec to_have_post_data(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_post_data(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:request, key}, :request_post_data, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request's page to equal the supplied value.
  """
  @spec to_have_page(term(), term(), [Expect.option()]) :: Expect.t()
  def to_have_page(key, expected, options \\ []) do
    Expect.new({:request, key}, :request_page, expected, options)
  end
end
