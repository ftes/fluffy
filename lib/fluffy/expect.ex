defmodule Fluffy.Expect do
  @moduledoc """
  Typed locator and active-page assertion values executed by
  `Fluffy.Expect.expect/2`.

  Page constructors use target prefixes such as `page_to_have_url/2`.
  Import this module to use `expect/2`, `not_/1`, and all constructors.
  For ExUnit-style names, use `Fluffy.Assert`.

  Assertion constructors use fluent `to_be_*` names for states and `to_have_*`
  names for properties.

  Every expectation constructor accepts the shared timeout option.

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

  @type target :: {:locator, Locator.t()} | :page

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
    end
  end

  @doc """
  Registers before the action, awaits a matching event, and optionally asserts on
  its value. Action and assertion callbacks run once in the caller; their return
  values are ignored. Returns the input session, retaining its page selection.
  """
  def expect_event(session, event, action), do: Fluffy.Event.expect(session, event, action, nil, [])

  @doc "Expects an event with an assertion callback or wait options."
  def expect_event(session, event, action, assertion) when is_function(assertion, 1),
    do: Fluffy.Event.expect(session, event, action, assertion, [])

  def expect_event(session, event, action, options) when is_list(options),
    do: Fluffy.Event.expect(session, event, action, nil, options)

  @doc "Expects an event with an assertion callback and wait options."
  def expect_event(session, event, action, assertion, options) when is_function(assertion, 1) and is_list(options),
    do: Fluffy.Event.expect(session, event, action, assertion, options)

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
  that complete serialized URL. A function receives a `%URI{}` and returns a boolean.
  Keep predicates quick and nonblocking.

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

  def page_to_have_url(expected, options)
      when (is_binary(expected) or is_struct(expected, Regex) or is_function(expected, 1)) and is_list(options) do
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
    actual = Fluffy.Page.status(Session.handle(session))
    assert_expected!(expectation, actual)
    session
  end

  defp expect_active_page(%Session{} = session, %Expect{kind: :opener} = expectation) do
    actual = session |> Session.handle() |> Fluffy.Page.opener() |> opener_value(expectation.expected)
    assert_expected!(expectation, actual)
    session
  end

  defp expect_active_page(_session, %Expect{} = expectation) do
    raise ArgumentError, "unsupported active page expectation: #{Expect.describe(expectation)}"
  end

  defp opener_value(nil, _expected), do: nil
  defp opener_value(page, %Fluffy.Page{}), do: page
  defp opener_value(page, _expected), do: Fluffy.Page.name(page)

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
