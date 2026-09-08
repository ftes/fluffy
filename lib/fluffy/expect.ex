defmodule Fluffy.Expect do
  @moduledoc """
  Typed locator, active-page, and captured-result assertion values executed by
  `Fluffy.expect/2`.

  Active page expectations live on `Fluffy.Page`. Captured-result expectations
  live on `Fluffy.Download`, `Fluffy.Dialog`, `Fluffy.Navigation`,
  `Fluffy.Request`, and `Fluffy.Response`.

  Assertion constructors use fluent `to_be_*` names for states and `to_have_*`
  names for properties, matching the page assertions in `Fluffy.Page`.

  Every expectation constructor accepts the shared timeout option. Captured-result
  assertions inspect an already retained result immediately; their timeout option
  does not wait for another event. Set the capture timeout on `Fluffy.wait_for/4`.

  #{NimbleOptions.docs(Fluffy.Options.expectation_schema())}

  `to_be_checked/2` additionally accepts:

  #{NimbleOptions.docs(Fluffy.Options.checked_expectation_schema())}
  """
  @moduledoc groups: ["Locator assertions"]

  alias Fluffy.Locator
  alias Fluffy.Options

  @enforce_keys [:target, :kind]
  defstruct [:target, :kind, :expected, options: [], negated?: false]

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
    "active page to have URL #{Fluffy.URLMatcher.describe(expected)}"
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

    "to have #{property} #{Fluffy.URLMatcher.describe(expected)}"
  end

  defp maybe_negated(description, false), do: description
  defp maybe_negated(description, true), do: "not " <> description

  defp normalize_title(title) do
    title
    |> String.replace(["\u200B", "\u00AD"], "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
