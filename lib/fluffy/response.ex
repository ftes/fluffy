defmodule Fluffy.Response do
  @moduledoc """
  Assertions for response results captured by `Fluffy.Event.response/3`.

  Pass the capture key as the first argument and execute the returned assertion
  with `Fluffy.expect/2`. Capture waits for the event; assertions inspect its
  retained result. Options follow `Fluffy.Expect`.
  """

  alias Fluffy.Expect
  alias Fluffy.URLMatcher

  @doc group: "Assertions"
  @doc """
  Expects the HTTP method of the request that produced this response.
  """
  @spec to_have_request_method(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_request_method(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:response, key}, :response_method, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Page.to_have_url/2`.
  """
  @spec to_have_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def to_have_url(key, expected, options \\ [])

  def to_have_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:response, key}, :response_url, expected, options)
  end

  def to_have_url(key, components, options) when is_list(components) do
    Expect.new({:response, key}, :response_url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response headers to include every supplied key/value pair. Additional
  headers are allowed.
  """
  @spec to_have_headers(term(), map(), [Expect.option()]) :: Expect.t()
  def to_have_headers(key, expected, options \\ []) when is_map(expected) do
    Expect.new({:response, key}, :response_headers, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response's resource type to equal the supplied value.
  """
  @spec to_have_resource_type(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_resource_type(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:response, key}, :response_resource_type, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the associated request payload to equal the supplied string. This does not inspect the
  response body.
  """
  @spec to_have_request_post_data(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_request_post_data(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:response, key}, :response_post_data, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response's status to equal the supplied value.
  """
  @spec to_have_status(term(), integer(), [Expect.option()]) :: Expect.t()
  def to_have_status(key, expected, options \\ []) when is_integer(expected) do
    Expect.new({:response, key}, :response_status, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response's status text to equal the supplied value.
  """
  @spec to_have_status_text(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_status_text(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:response, key}, :response_status_text, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response's page to equal the supplied value.
  """
  @spec to_have_page(term(), term(), [Expect.option()]) :: Expect.t()
  def to_have_page(key, expected, options \\ []) do
    Expect.new({:response, key}, :response_page, expected, options)
  end
end
