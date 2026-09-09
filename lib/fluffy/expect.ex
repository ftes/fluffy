defmodule Fluffy.Expect do
  @moduledoc """
  Typed locator, active-page, and captured-result assertion values executed by
  `Fluffy.Expect.expect/2`.

  Page and captured-result constructors use target prefixes such as
  `page_to_have_url/2` and `response_to_have_status/3`.
  Import this module to use `expect/2`, `not_/1`, and all constructors.
  For ExUnit-style names, use `Fluffy.Assert`.

  Assertion constructors use fluent `to_be_*` names for states and `to_have_*`
  names for properties.

  Every expectation constructor accepts the shared timeout option. Captured-result
  assertions inspect an already retained result immediately; their timeout option
  does not wait for another event. Set the capture timeout on `Fluffy.wait_for/4`.

  #{NimbleOptions.docs(Fluffy.Options.expectation_schema())}

  `to_be_checked/2` additionally accepts:

  #{NimbleOptions.docs(Fluffy.Options.checked_expectation_schema())}
  """
  @moduledoc groups: ["Locator assertions"]

  alias Fluffy.Expect
  alias Fluffy.Locator
  alias Fluffy.Options
  alias Fluffy.Session
  alias Fluffy.URLMatcher

  @enforce_keys [:target, :kind]
  defstruct [:target, :kind, :expected, options: [], negated?: false]

  @dialyzer {:nowarn_function, expect: 3}

  @type target ::
          {:locator, Locator.t()}
          | :page
          | {:download, term()}
          | {:dialog, term()}
          | {:navigation, term()}
          | {:request, term()}
          | {:response, term()}

  @type kind ::
          :checked
          | :count
          | :disabled
          | :editable
          | :enabled
          | :focused
          | :opener
          | :status
          | :title
          | :url
          | :value
          | :values
          | :visible
          | :download_content
          | :download_content_type
          | :download_size
          | :download_suggested_filename
          | :download_url
          | :dialog_action
          | :dialog_default_value
          | :dialog_message
          | :dialog_prompt_text
          | :dialog_type
          | :navigation_from_url
          | :navigation_status
          | :navigation_url
          | :request_headers
          | :request_method
          | :request_page
          | :request_post_data
          | :request_resource_type
          | :request_url
          | :response_headers
          | :response_method
          | :response_page
          | :response_post_data
          | :response_resource_type
          | :response_status
          | :response_status_text
          | :response_url

  @type t :: %__MODULE__{
          target: target(),
          kind: kind(),
          expected: term(),
          options: keyword(),
          negated?: boolean()
        }

  @type option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema()))
  @type checked_option :: unquote(NimbleOptions.option_typespec(Options.checked_expectation_schema()))

  @doc "Executes an expectation and returns the unchanged or reconciled session."
  @spec expect(Session.t(), t(), [option()]) :: Session.t()
  def expect(%Session{} = session, %Expect{} = expectation, options \\ []) do
    expectation =
      expectation
      |> Expect.merge_options(options)
      |> normalize_expectation(session)

    case expectation.target do
      {:locator, _locator} ->
        Fluffy.__expect__(session, expectation)

      :page ->
        expect_active_page(session, expectation)

      {type, key} when type in [:download, :dialog, :navigation, :request, :response] ->
        expect_captured_result(session, type, key, expectation)
    end
  end

  @doc "Negates an expectation while preserving its target and options."
  @spec not_(t()) :: t()
  def not_(%__MODULE__{} = expectation), do: negate(expectation)

  @doc group: "Locator assertions"
  @spec to_have_count(Locator.t(), non_neg_integer(), [option()]) :: t()
  def to_have_count(%Locator{} = locator, expected, options \\ []) when is_integer(expected) and expected >= 0 do
    new({:locator, locator}, :count, expected, options)
  end

  @doc group: "Locator assertions"
  @spec to_be_visible(Locator.t(), [option()]) :: t()
  def to_be_visible(%Locator{} = locator, options \\ []) do
    new({:locator, locator}, :visible, true, options)
  end

  @doc group: "Locator assertions"
  @spec to_be_disabled(Locator.t(), [option()]) :: t()
  def to_be_disabled(%Locator{} = locator, options \\ []) do
    new({:locator, locator}, :disabled, true, options)
  end

  @doc group: "Locator assertions"
  @spec to_be_editable(Locator.t(), [option()]) :: t()
  def to_be_editable(%Locator{} = locator, options \\ []) do
    new({:locator, locator}, :editable, true, options)
  end

  @doc group: "Locator assertions"
  @spec to_be_enabled(Locator.t(), [option()]) :: t()
  def to_be_enabled(%Locator{} = locator, options \\ []) do
    new({:locator, locator}, :enabled, true, options)
  end

  @doc group: "Locator assertions"
  @spec to_be_focused(Locator.t(), [option()]) :: t()
  def to_be_focused(%Locator{} = locator, options \\ []) do
    new({:locator, locator}, :focused, true, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects a checkbox or radio to have Playwright's checked state.

  The default is checked. Pass `checked: false` for unchecked, or
  `indeterminate: true` for the browser-owned mixed state. The indeterminate
  state requires Playwright because it is a DOM property rather than HTML
  state available to the Static or LiveView drivers.
  """
  @spec to_be_checked(Locator.t(), [checked_option()]) :: t()
  def to_be_checked(%Locator{} = locator, options \\ []) do
    options = Options.validate_checked_expectation!(options)
    checked = Keyword.get(options, :checked, :unset)
    indeterminate = Keyword.get(options, :indeterminate, :unset)

    if indeterminate == true and checked != :unset do
      raise ArgumentError, "checked: and indeterminate: true cannot be used together"
    end

    expected =
      cond do
        indeterminate == true -> :indeterminate
        checked == false -> :unchecked
        true -> :checked
      end

    new({:locator, locator}, :checked, expected, Keyword.take(options, [:timeout]))
  end

  @doc group: "Locator assertions"
  @spec to_have_value(Locator.t(), String.t(), [option()]) :: t()
  def to_have_value(%Locator{} = locator, expected, options \\ []) when is_binary(expected) do
    new({:locator, locator}, :value, expected, options)
  end

  @doc group: "Locator assertions"
  @spec to_have_values(Locator.t(), [term()], [option()]) :: t()
  def to_have_values(%Locator{} = locator, expected, options \\ []) when is_list(expected) do
    new({:locator, locator}, :values, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the active page title to equal a string or match a regular expression.

  Like Playwright's `toHaveTitle`, the assertion retries on Live and Playwright
  pages and normalizes whitespace before matching.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema())}
  """
  @spec page_to_have_title(Fluffy.Page.title_expectation()) :: Expect.t()
  @spec page_to_have_title(Fluffy.Page.title_expectation(), [Expect.option()]) :: Expect.t()
  def page_to_have_title(expected, options \\ [])
      when (is_binary(expected) or is_struct(expected, Regex)) and is_list(options) do
    Expect.new(:page, :title, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the active page to have the requested URL.

  A string matches the complete canonical absolute URL after resolving a
  relative value against the session base URL. A regular expression matches
  that complete serialized URL.

  A keyword list selects structured components. `:path` and `:fragment` are
  exact serialized component values; omit either to ignore it. `:fragment`
  excludes the leading `#`, and `fragment: nil` requires no fragment.

  `:query` is a map from decoded parameter names to one value or an ordered
  list of repeated values. Ordering between distinct names is ignored while
  repeated-value order is retained. Bare names and names with an empty value
  both decode to `""`; `+` and `%20` both decode to a space. Exact mode is the
  default. `query_mode: :subset` permits unrelated names but still requires
  the complete ordered value list for each requested name.

  ## Structured components

  #{NimbleOptions.docs(Options.url_matcher_schema())}

  ## Assertion options

  #{NimbleOptions.docs(Options.expectation_schema())}
  """
  @spec page_to_have_url(Fluffy.Page.url_expectation()) :: Expect.t()
  @spec page_to_have_url(Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def page_to_have_url(expected, options \\ [])

  def page_to_have_url(expected, options) when (is_binary(expected) or is_struct(expected, Regex)) and is_list(options) do
    Expect.new(:page, :url, expected, options)
  end

  def page_to_have_url(components, options) when is_list(components) and is_list(options) do
    Expect.new(:page, :url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc "Expects the active page's normalized main-resource status."
  @spec page_to_have_status(non_neg_integer(), [Expect.option()]) :: Expect.t()
  def page_to_have_status(expected, options \\ []) when is_integer(expected) and expected >= 0 do
    Expect.new(:page, :status, expected, options)
  end

  @doc group: "Assertions"
  @doc "Expects the active page to name the requested opener page."
  @spec page_to_have_opener(term(), [Expect.option()]) :: Expect.t()
  def page_to_have_opener(expected, options \\ []) when is_list(options) do
    Expect.new(:page, :opener, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured download's suggested filename to equal the supplied value.
  """
  @spec download_to_have_suggested_filename(term(), String.t(), [Expect.option()]) :: Expect.t()
  def download_to_have_suggested_filename(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:download, key}, :download_suggested_filename, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured download's content type to equal the supplied value.
  """
  @spec download_to_have_content_type(term(), String.t(), [Expect.option()]) :: Expect.t()
  def download_to_have_content_type(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:download, key}, :download_content_type, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the complete downloaded bytes to equal the supplied binary; no text decoding is
  performed.
  """
  @spec download_to_have_content(term(), binary(), [Expect.option()]) :: Expect.t()
  def download_to_have_content(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:download, key}, :download_content, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the download size in bytes.
  """
  @spec download_to_have_size(term(), non_neg_integer(), [Expect.option()]) :: Expect.t()
  def download_to_have_size(key, expected, options \\ []) when is_integer(expected) and expected >= 0 do
    Expect.new({:download, key}, :download_size, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured download URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Expect.page_to_have_url/2`.
  """
  @spec download_to_have_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def download_to_have_url(key, expected, options \\ [])

  def download_to_have_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:download, key}, :download_url, expected, options)
  end

  def download_to_have_url(key, components, options) when is_list(components) do
    Expect.new({:download, key}, :download_url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's type to equal the supplied value.
  """
  @spec dialog_to_have_type(term(), term(), [Expect.option()]) :: Expect.t()
  def dialog_to_have_type(key, expected, options \\ []) do
    Expect.new({:dialog, key}, :dialog_type, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's message to equal the supplied value.
  """
  @spec dialog_to_have_message(term(), String.t(), [Expect.option()]) :: Expect.t()
  def dialog_to_have_message(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:dialog, key}, :dialog_message, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's default value to equal the supplied value.
  """
  @spec dialog_to_have_default_value(term(), String.t(), [Expect.option()]) :: Expect.t()
  def dialog_to_have_default_value(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:dialog, key}, :dialog_default_value, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's action to equal the supplied value.
  """
  @spec dialog_to_have_action(term(), term(), [Expect.option()]) :: Expect.t()
  def dialog_to_have_action(key, expected, options \\ []) do
    Expect.new({:dialog, key}, :dialog_action, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's prompt text to equal the supplied value.
  """
  @spec dialog_to_have_prompt_text(term(), term(), [Expect.option()]) :: Expect.t()
  def dialog_to_have_prompt_text(key, expected, options \\ []) do
    Expect.new({:dialog, key}, :dialog_prompt_text, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured navigation URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Expect.page_to_have_url/2`.
  """
  @spec navigation_to_have_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def navigation_to_have_url(key, expected, options \\ [])

  def navigation_to_have_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:navigation, key}, :navigation_url, expected, options)
  end

  def navigation_to_have_url(key, components, options) when is_list(components) do
    Expect.new({:navigation, key}, :navigation_url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured navigation source URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Expect.page_to_have_url/2`.
  """
  @spec navigation_to_have_from_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def navigation_to_have_from_url(key, expected, options \\ [])

  def navigation_to_have_from_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:navigation, key}, :navigation_from_url, expected, options)
  end

  def navigation_to_have_from_url(key, components, options) when is_list(components) do
    Expect.new({:navigation, key}, :navigation_from_url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured navigation's status to equal the supplied value.
  """
  @spec navigation_to_have_status(term(), integer(), [Expect.option()]) :: Expect.t()
  def navigation_to_have_status(key, expected, options \\ []) when is_integer(expected) do
    Expect.new({:navigation, key}, :navigation_status, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request's method to equal the supplied value.
  """
  @spec request_to_have_method(term(), String.t(), [Expect.option()]) :: Expect.t()
  def request_to_have_method(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:request, key}, :request_method, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Expect.page_to_have_url/2`.
  """
  @spec request_to_have_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def request_to_have_url(key, expected, options \\ [])

  def request_to_have_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:request, key}, :request_url, expected, options)
  end

  def request_to_have_url(key, components, options) when is_list(components) do
    Expect.new({:request, key}, :request_url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request headers to include every supplied key/value pair. Additional
  headers are allowed.
  """
  @spec request_to_have_headers(term(), map(), [Expect.option()]) :: Expect.t()
  def request_to_have_headers(key, expected, options \\ []) when is_map(expected) do
    Expect.new({:request, key}, :request_headers, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request's resource type to equal the supplied value.
  """
  @spec request_to_have_resource_type(term(), String.t(), [Expect.option()]) :: Expect.t()
  def request_to_have_resource_type(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:request, key}, :request_resource_type, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request's post data to equal the supplied value.
  """
  @spec request_to_have_post_data(term(), String.t(), [Expect.option()]) :: Expect.t()
  def request_to_have_post_data(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:request, key}, :request_post_data, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured request's page to equal the supplied value.
  """
  @spec request_to_have_page(term(), term(), [Expect.option()]) :: Expect.t()
  def request_to_have_page(key, expected, options \\ []) do
    Expect.new({:request, key}, :request_page, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the HTTP method of the request that produced this response.
  """
  @spec response_to_have_request_method(term(), String.t(), [Expect.option()]) :: Expect.t()
  def response_to_have_request_method(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:response, key}, :response_method, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response URL to match a string, regex, or structured components.

  Strings match exactly and regexes match against the complete captured URL.
  Relative strings are not resolved. Structured keywords use the same path,
  query, and fragment rules as `Fluffy.Expect.page_to_have_url/2`.
  """
  @spec response_to_have_url(term(), Fluffy.Page.url_expectation(), [Expect.option()]) :: Expect.t()
  def response_to_have_url(key, expected, options \\ [])

  def response_to_have_url(key, expected, options) when is_binary(expected) or is_struct(expected, Regex) do
    Expect.new({:response, key}, :response_url, expected, options)
  end

  def response_to_have_url(key, components, options) when is_list(components) do
    Expect.new({:response, key}, :response_url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response headers to include every supplied key/value pair. Additional
  headers are allowed.
  """
  @spec response_to_have_headers(term(), map(), [Expect.option()]) :: Expect.t()
  def response_to_have_headers(key, expected, options \\ []) when is_map(expected) do
    Expect.new({:response, key}, :response_headers, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response's resource type to equal the supplied value.
  """
  @spec response_to_have_resource_type(term(), String.t(), [Expect.option()]) :: Expect.t()
  def response_to_have_resource_type(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:response, key}, :response_resource_type, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the associated request payload to equal the supplied string. This does not inspect the
  response body.
  """
  @spec response_to_have_request_post_data(term(), String.t(), [Expect.option()]) :: Expect.t()
  def response_to_have_request_post_data(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:response, key}, :response_post_data, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response's status to equal the supplied value.
  """
  @spec response_to_have_status(term(), integer(), [Expect.option()]) :: Expect.t()
  def response_to_have_status(key, expected, options \\ []) when is_integer(expected) do
    Expect.new({:response, key}, :response_status, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response's status text to equal the supplied value.
  """
  @spec response_to_have_status_text(term(), String.t(), [Expect.option()]) :: Expect.t()
  def response_to_have_status_text(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:response, key}, :response_status_text, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured response's page to equal the supplied value.
  """
  @spec response_to_have_page(term(), term(), [Expect.option()]) :: Expect.t()
  def response_to_have_page(key, expected, options \\ []) do
    Expect.new({:response, key}, :response_page, expected, options)
  end

  @doc false
  def matches?(%Regex{} = expected, actual) when is_binary(actual), do: Regex.match?(expected, actual)

  def matches?(expected, actual), do: actual == expected

  @doc false
  def title_matches?(expected, actual) when is_binary(actual) do
    actual = normalize_title(actual)

    case expected do
      %Regex{} -> matches?(expected, actual)
      expected when is_binary(expected) -> normalize_title(expected) == actual
    end
  end

  def title_matches?(_expected, _actual), do: false

  @doc false
  def new(target, kind, expected, options \\ []) when is_atom(kind) and is_list(options) do
    %__MODULE__{
      target: target,
      kind: kind,
      expected: expected,
      options: validate_options!(options)
    }
  end

  @doc false
  def negate(%__MODULE__{} = expectation) do
    %{expectation | negated?: not expectation.negated?}
  end

  @doc false
  def merge_options(%__MODULE__{} = expectation, options) when is_list(options) do
    %{expectation | options: Keyword.merge(expectation.options, validate_options!(options))}
  end

  @doc false
  def result_field(%__MODULE__{kind: :download_suggested_filename}), do: :filename
  def result_field(%__MODULE__{kind: :download_content_type}), do: :content_type
  def result_field(%__MODULE__{kind: :download_content}), do: :bytes
  def result_field(%__MODULE__{kind: :download_size}), do: :bytes
  def result_field(%__MODULE__{kind: :download_url}), do: :url
  def result_field(%__MODULE__{kind: :dialog_type}), do: :type
  def result_field(%__MODULE__{kind: :dialog_message}), do: :message
  def result_field(%__MODULE__{kind: :dialog_default_value}), do: :default_value
  def result_field(%__MODULE__{kind: :dialog_action}), do: :action
  def result_field(%__MODULE__{kind: :dialog_prompt_text}), do: :prompt_text
  def result_field(%__MODULE__{kind: :navigation_url}), do: :url
  def result_field(%__MODULE__{kind: :navigation_from_url}), do: :from_url
  def result_field(%__MODULE__{kind: :navigation_status}), do: :status
  def result_field(%__MODULE__{kind: :request_method}), do: :method
  def result_field(%__MODULE__{kind: :request_url}), do: :url
  def result_field(%__MODULE__{kind: :request_headers}), do: :headers
  def result_field(%__MODULE__{kind: :request_resource_type}), do: :resource_type
  def result_field(%__MODULE__{kind: :request_post_data}), do: :post_data
  def result_field(%__MODULE__{kind: :request_page}), do: :page
  def result_field(%__MODULE__{kind: :response_method}), do: :method
  def result_field(%__MODULE__{kind: :response_url}), do: :url
  def result_field(%__MODULE__{kind: :response_headers}), do: :headers
  def result_field(%__MODULE__{kind: :response_resource_type}), do: :resource_type
  def result_field(%__MODULE__{kind: :response_post_data}), do: :post_data
  def result_field(%__MODULE__{kind: :response_status}), do: :status
  def result_field(%__MODULE__{kind: :response_status_text}), do: :status_text
  def result_field(%__MODULE__{kind: :response_page}), do: :page

  @doc false
  def describe(%__MODULE__{} = expectation) do
    expectation
    |> positive_description()
    |> maybe_negated(expectation.negated?)
  end

  defp validate_options!(options), do: Options.validate_expectation!(options)

  defp positive_description(%__MODULE__{target: {:locator, locator}, kind: kind, expected: expected}) do
    "#{Locator.describe(locator)} #{locator_matcher_description(kind, expected)}"
  end

  defp positive_description(%__MODULE__{target: :page, kind: :url, expected: expected}) do
    "active page to have URL #{URLMatcher.describe(expected)}"
  end

  defp positive_description(%__MODULE__{target: :page, kind: :status, expected: expected}) do
    "active page to have status #{inspect(expected)}"
  end

  defp positive_description(%__MODULE__{target: :page, kind: :title, expected: expected}) do
    "active page to have title #{inspect(expected)}"
  end

  defp positive_description(%__MODULE__{target: :page, kind: :opener, expected: expected}) do
    "active page to have opener #{inspect(expected)}"
  end

  defp positive_description(%__MODULE__{target: {type, key}, kind: kind, expected: expected}) do
    "#{type} #{inspect(key)} #{result_matcher_description(kind, expected)}"
  end

  defp locator_matcher_description(:checked, :checked), do: "to be checked"
  defp locator_matcher_description(:checked, :unchecked), do: "to be unchecked"
  defp locator_matcher_description(:checked, :indeterminate), do: "to be indeterminate"
  defp locator_matcher_description(:count, expected), do: "to have count #{inspect(expected)}"
  defp locator_matcher_description(:disabled, _expected), do: "to be disabled"
  defp locator_matcher_description(:editable, _expected), do: "to be editable"
  defp locator_matcher_description(:enabled, _expected), do: "to be enabled"
  defp locator_matcher_description(:focused, _expected), do: "to be focused"
  defp locator_matcher_description(:value, expected), do: "to have value #{inspect(expected)}"
  defp locator_matcher_description(:values, expected), do: "to have values #{inspect(expected)}"
  defp locator_matcher_description(:visible, _expected), do: "to be visible"

  defp result_matcher_description(kind, expected) do
    property =
      case kind do
        :response_method -> "request method"
        :response_post_data -> "request post data"
        _ -> kind |> Atom.to_string() |> String.split("_", parts: 2) |> List.last() |> String.replace("_", " ")
      end

    "to have #{property} #{URLMatcher.describe(expected)}"
  end

  defp maybe_negated(description, false), do: description
  defp maybe_negated(description, true), do: "not " <> description

  defp normalize_title(title) do
    title
    |> String.replace(["\u200B", "\u00AD"], "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp expect_active_page(%Session{} = session, %Expect{kind: :url} = expectation) do
    Fluffy.__expect__(session, expectation)
  end

  defp expect_active_page(%Session{} = session, %Expect{kind: :title} = expectation) do
    Fluffy.__expect__(session, expectation)
  end

  defp expect_active_page(%Session{} = session, %Expect{kind: :status} = expectation) do
    actual = Session.current_page(session).status
    assert_expected!(expectation, actual)
    session
  end

  defp expect_active_page(%Session{} = session, %Expect{kind: :opener} = expectation) do
    actual = Session.current_page(session).opener
    assert_expected!(expectation, actual)
    session
  end

  defp expect_active_page(_session, %Expect{} = expectation) do
    raise ArgumentError, "unsupported active page expectation: #{Expect.describe(expectation)}"
  end

  defp expect_captured_result(%Session{} = session, type, key, %Expect{} = expectation) do
    result = Session.fetch_result!(session, key, type)
    field = Expect.result_field(expectation)
    actual = Map.fetch!(result, field)
    actual = if expectation.kind == :download_size, do: byte_size(actual), else: actual

    assert_expected!(expectation, actual)
    session
  end

  defp assert_expected!(%Expect{kind: :request_headers} = expectation, actual) do
    expected = expectation.expected
    passed? = Map.take(actual, Map.keys(expected)) == expected
    assert_expectation_truth!(expectation, passed?, actual)
  end

  defp assert_expected!(%Expect{kind: :response_headers} = expectation, actual) do
    expected = expectation.expected
    passed? = Map.take(actual, Map.keys(expected)) == expected
    assert_expectation_truth!(expectation, passed?, actual)
  end

  defp assert_expected!(%Expect{kind: kind} = expectation, actual)
       when kind in [:download_url, :navigation_url, :navigation_from_url, :request_url, :response_url] do
    assert_expectation_truth!(expectation, URLMatcher.matches?(expectation.expected, actual), actual)
  end

  defp assert_expected!(%Expect{} = expectation, actual) do
    assert_expectation_truth!(expectation, Expect.matches?(expectation.expected, actual), actual)
  end

  defp assert_expectation_truth!(%Expect{} = expectation, passed?, actual) do
    if passed? == expectation.negated? do
      raise ExUnit.AssertionError,
        message: "Expected #{Expect.describe(expectation)}, got #{inspect(actual)}"
    end

    :ok
  end

  defp normalize_expectation(%Expect{target: :page, kind: :url, expected: expected} = expectation, session)
       when is_binary(expected) do
    %{expectation | expected: Fluffy.Backend.absolute_url(session, expected)}
  end

  defp normalize_expectation(%Expect{} = expectation, _session), do: expectation
end
