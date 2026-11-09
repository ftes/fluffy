defmodule Fluffy.Expect do
  @moduledoc """
  Typed locator and active-page assertion values executed by
  `Fluffy.Expect.expect/2`.

  Page constructors use target prefixes such as `page_to_have_url/2`.
  Import this module to use `expect/2`, `not_/1`, and all constructors.
  For ExUnit-style names, use `Fluffy.Assert`.

  Assertion constructors use fluent `to_be_*` names for states and `to_have_*`
  names for properties.

  Every constructor documents its options. `expect/3` accepts the shared timeout:

  #{NimbleOptions.docs(Fluffy.Options.expectation_schema())}
  """
  @moduledoc groups: ["Locator assertions"]

  alias Fluffy.Expect
  alias Fluffy.Expect.Internal
  alias Fluffy.Locator
  alias Fluffy.Options
  alias Fluffy.Session
  alias Fluffy.URLMatcher

  @enforce_keys [:target, :kind]
  defstruct [:target, :kind, :expected, options: [], negated?: false]

  @dialyzer {:nowarn_function, expect: 3}

  @type target :: {:locator, Locator.t()} | :page

  @type kind ::
          :attached
          | :attribute
          | :checked
          | :class
          | :contain_class
          | :contain_text
          | :count
          | :disabled
          | :editable
          | :empty
          | :enabled
          | :focused
          | :hidden
          | :id
          | :in_viewport
          | :opener
          | :text
          | :title
          | :url
          | :value
          | :values
          | :visible

  @type text_expectation :: String.t() | Regex.t()

  @type t :: %__MODULE__{
          target: target(),
          kind: kind(),
          expected: term(),
          options: keyword(),
          negated?: boolean()
        }

  @type option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema()))
  @type to_have_count_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_count)))
  @type to_be_visible_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_visible)))
  @type to_be_disabled_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_disabled)))
  @type to_be_editable_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_editable)))
  @type to_be_enabled_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_enabled)))
  @type to_be_focused_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_focused)))
  @type to_be_in_viewport_option ::
          unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_in_viewport)))
  @type to_be_checked_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_checked)))
  @type to_have_value_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_value)))
  @type to_have_values_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_values)))
  @type to_have_text_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_text)))
  @type to_contain_text_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_contain_text)))
  @type to_have_attribute_option ::
          unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_attribute)))
  @type to_have_class_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_class)))
  @type to_contain_class_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_contain_class)))
  @type to_have_id_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_id)))
  @type to_be_attached_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_attached)))
  @type to_be_hidden_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_hidden)))
  @type to_be_empty_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_be_empty)))
  @type page_to_have_title_option ::
          unquote(NimbleOptions.option_typespec(Options.expectation_schema(:page_to_have_title)))
  @type page_to_have_url_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:page_to_have_url)))

  @doc "Executes an expectation and returns the unchanged or reconciled session."
  @spec expect(Session.t(), t(), [option()]) :: Session.t()
  def expect(%Session{} = session, %Expect{} = expectation, options \\ []) do
    expectation =
      expectation
      |> Internal.merge_options(options)
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
  def not_(%__MODULE__{} = expectation), do: Internal.negate(expectation)

  @doc group: "Locator assertions"
  @doc """
  Expects the number of elements matching the locator.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_count))}
  """
  @spec to_have_count(Locator.t(), non_neg_integer(), [to_have_count_option()]) :: t()
  def to_have_count(%Locator{} = locator, expected, options \\ []) when is_integer(expected) and expected >= 0 do
    native_expectation(:to_have_count, {:locator, locator}, :count, expected, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target to be visible.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_visible))}
  """
  @spec to_be_visible(Locator.t(), [to_be_visible_option()]) :: t()
  def to_be_visible(%Locator{} = locator, options \\ []) do
    state_expectation(:to_be_visible, locator, :visible, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target to be disabled.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_disabled))}
  """
  @spec to_be_disabled(Locator.t(), [to_be_disabled_option()]) :: t()
  def to_be_disabled(%Locator{} = locator, options \\ []) do
    native_expectation(:to_be_disabled, {:locator, locator}, :disabled, true, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target to be editable.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_editable))}
  """
  @spec to_be_editable(Locator.t(), [to_be_editable_option()]) :: t()
  def to_be_editable(%Locator{} = locator, options \\ []) do
    state_expectation(:to_be_editable, locator, :editable, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target to be enabled.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_enabled))}
  """
  @spec to_be_enabled(Locator.t(), [to_be_enabled_option()]) :: t()
  def to_be_enabled(%Locator{} = locator, options \\ []) do
    state_expectation(:to_be_enabled, locator, :enabled, options)
  end

  @doc group: "Locator assertions"
  @doc playwright_only: true
  @doc """
  Asserts browser focus. Requires Playwright, including when negated.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_focused))}
  """
  @spec to_be_focused(Locator.t(), [to_be_focused_option()]) :: t()
  def to_be_focused(%Locator{} = locator, options \\ []) do
    native_expectation(:to_be_focused, {:locator, locator}, :focused, true, options)
  end

  @doc group: "Locator assertions"
  @doc playwright_only: true
  @doc """
  Asserts that the target intersects the viewport. Requires Playwright, including when negated.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_in_viewport))}
  """
  @spec to_be_in_viewport(Locator.t(), [to_be_in_viewport_option()]) :: t()
  def to_be_in_viewport(%Locator{} = locator, options \\ []) do
    options = Options.validate_expectation!(:to_be_in_viewport, options)
    {matching, options} = Keyword.split(options, [:ratio])
    Internal.new({:locator, locator}, :in_viewport, matching, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects a checkbox or radio to have Playwright's checked state.

  The default is checked. Pass `checked: false` for unchecked, or
  `indeterminate: true` for the browser-owned mixed state. The indeterminate
  state requires Playwright because it is a DOM property rather than HTML
  state available to the Static or LiveView drivers.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_checked))}
  """
  @spec to_be_checked(Locator.t(), [to_be_checked_option()]) :: t()
  def to_be_checked(%Locator{} = locator, options \\ []) do
    options = Options.validate_expectation!(:to_be_checked, options)
    {checked, options} = Keyword.pop(options, :checked, :unset)
    {indeterminate, options} = Keyword.pop(options, :indeterminate, :unset)

    if indeterminate == true and checked != :unset do
      raise ArgumentError, "checked: and indeterminate: true cannot be used together"
    end

    expected =
      cond do
        indeterminate == true -> :indeterminate
        checked == false -> :unchecked
        true -> :checked
      end

    Internal.new({:locator, locator}, :checked, expected, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target's input value.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_value))}
  """
  @spec to_have_value(Locator.t(), String.t(), [to_have_value_option()]) :: t()
  def to_have_value(%Locator{} = locator, expected, options \\ []) when is_binary(expected) do
    native_expectation(:to_have_value, {:locator, locator}, :value, expected, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the selected values of a multi-select.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_values))}
  """
  @spec to_have_values(Locator.t(), [term()], [to_have_values_option()]) :: t()
  def to_have_values(%Locator{} = locator, expected, options \\ []) when is_list(expected) do
    native_expectation(:to_have_values, {:locator, locator}, :values, expected, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target's text to equal a string or match a regular expression.

  Text is the element's `textContent` without `<script>`, `<style>`, and
  `<noscript>` content, with a submit, button, or reset input contributing its
  value. A string compares normalized whitespace in both the text and the
  expected value, while a regular expression sees the text as is.

  A list asserts every element the locator matches, in order: there must be as
  many elements as expected values, and each must match its value. Any other
  form requires exactly one element.

  Negation still requires the element, except in the list form, where no
  elements are simply a list that does not match.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_text))}
  """
  @spec to_have_text(Locator.t(), text_expectation() | [text_expectation()], [to_have_text_option()]) :: t()
  def to_have_text(%Locator{} = locator, expected, options \\ [])
      when is_binary(expected) or is_struct(expected, Regex) or is_list(expected) do
    text_expectation(:to_have_text, locator, :text, expected, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target's text to contain a string or match a regular expression.

  Reads and normalizes text like `to_have_text/3`. A list expects the values to
  match a subset of the elements the locator matches, in order; unlike
  `to_have_text/3`, the counts need not agree.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_contain_text))}
  """
  @spec to_contain_text(Locator.t(), text_expectation() | [text_expectation()], [to_contain_text_option()]) :: t()
  def to_contain_text(%Locator{} = locator, expected, options \\ [])
      when is_binary(expected) or is_struct(expected, Regex) or is_list(expected) do
    text_expectation(:to_contain_text, locator, :contain_text, expected, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target to have the attribute, optionally with the given value.

  A `nil` value asserts that the attribute is present; options may take its
  place. A string compares the exact attribute value, without whitespace
  normalization.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_attribute))}
  """
  @spec to_have_attribute(Locator.t(), String.t()) :: t()
  @spec to_have_attribute(Locator.t(), String.t(), text_expectation() | nil | [to_have_attribute_option()]) :: t()
  @spec to_have_attribute(Locator.t(), String.t(), text_expectation() | nil, [to_have_attribute_option()]) :: t()
  def to_have_attribute(locator, name, value \\ nil, options \\ [])

  def to_have_attribute(%Locator{} = locator, name, options, []) when is_binary(name) and is_list(options),
    do: to_have_attribute(locator, name, nil, options)

  def to_have_attribute(%Locator{} = locator, name, value, options)
      when is_binary(name) and (is_nil(value) or is_binary(value) or is_struct(value, Regex)) and is_list(options) do
    options = Options.validate_expectation!(:to_have_attribute, options)
    {matching, options} = Keyword.split(options, [:ignore_case])
    Internal.new({:locator, locator}, :attribute, {name, value, matching}, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target's `class` attribute to equal a string or match a regular
  expression. An element without one has an empty class.

  A list asserts every element the locator matches, in order, as in
  `to_have_text/3`. To match individual classes, use `to_contain_class/3`.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_class))}
  """
  @spec to_have_class(Locator.t(), text_expectation() | [text_expectation()], [to_have_class_option()]) :: t()
  def to_have_class(%Locator{} = locator, expected, options \\ [])
      when is_binary(expected) or is_struct(expected, Regex) or is_list(expected) do
    native_expectation(:to_have_class, {:locator, locator}, :class, text_values!(expected), options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target to have all the classes of a space-separated string, in any
  order.

  A list asserts every element the locator matches, in order, with one string
  for each element. Unlike `to_have_class/3`, this constructor takes no regular
  expression.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_contain_class))}
  """
  @spec to_contain_class(Locator.t(), String.t() | [String.t()], [to_contain_class_option()]) :: t()
  def to_contain_class(%Locator{} = locator, expected, options \\ []) when is_binary(expected) or is_list(expected) do
    if is_list(expected) and not Enum.all?(expected, &is_binary/1) do
      raise ArgumentError, "expected a string of class names for each element, got: #{inspect(expected)}"
    end

    native_expectation(:to_contain_class, {:locator, locator}, :contain_class, expected, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target's id to equal a string or match a regular expression. An
  element without one has an empty id.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_id))}
  """
  @spec to_have_id(Locator.t(), text_expectation(), [to_have_id_option()]) :: t()
  def to_have_id(%Locator{} = locator, expected, options \\ []) when is_binary(expected) or is_struct(expected, Regex) do
    native_expectation(:to_have_id, {:locator, locator}, :id, expected, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target to be attached to the document, visible or not.

  Pass `attached: false` to expect that nothing matches, like `not_/1`.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_attached))}
  """
  @spec to_be_attached(Locator.t(), [to_be_attached_option()]) :: t()
  def to_be_attached(%Locator{} = locator, options \\ []) do
    state_expectation(:to_be_attached, locator, :attached, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects the target to be hidden, which includes matching nothing.

  Negating it requires a visible element. Static and LiveView use the
  structural visibility of `to_be_visible/2`; see
  [Visibility and DOM presence](usage.md#visibility-and-dom-presence).

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_hidden))}
  """
  @spec to_be_hidden(Locator.t(), [to_be_hidden_option()]) :: t()
  def to_be_hidden(%Locator{} = locator, options \\ []) do
    native_expectation(:to_be_hidden, {:locator, locator}, :hidden, true, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Expects an input or textarea to have no value, or any other element to have no
  text besides whitespace.

  Negation still requires the element.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_be_empty))}
  """
  @spec to_be_empty(Locator.t(), [to_be_empty_option()]) :: t()
  def to_be_empty(%Locator{} = locator, options \\ []) do
    native_expectation(:to_be_empty, {:locator, locator}, :empty, true, options)
  end

  # `visible: false` and the like assert the opposite state, as in PlaywrightEx.
  defp state_expectation(matcher, locator, kind, options) do
    options = Options.validate_expectation!(matcher, options)
    {state, options} = Keyword.pop(options, kind, true)
    expectation = Internal.new({:locator, locator}, kind, true, options)
    if state, do: expectation, else: Internal.negate(expectation)
  end

  defp native_expectation(matcher, target, kind, expected, options),
    do: Internal.new(target, kind, expected, Options.validate_expectation!(matcher, options))

  # The options that select how text is read and compared travel with the expected value.
  defp text_expectation(matcher, locator, kind, expected, options) do
    options = Options.validate_expectation!(matcher, options)
    {matching, options} = Keyword.split(options, [:ignore_case, :use_inner_text])
    Internal.new({:locator, locator}, kind, {text_values!(expected), matching}, options)
  end

  defp text_values!(expected) when is_list(expected) do
    if Enum.all?(expected, &(is_binary(&1) or is_struct(&1, Regex))) do
      expected
    else
      raise ArgumentError, "expected a list of strings or regular expressions, got: #{inspect(expected)}"
    end
  end

  defp text_values!(expected), do: expected

  @doc group: "Assertions"
  @doc """
  Expects the active page title to equal a string or match a regular expression.

  Like Playwright's `toHaveTitle`, the assertion retries on Live and Playwright
  pages and normalizes whitespace before matching.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:page_to_have_title))}
  """
  @spec page_to_have_title(Fluffy.Page.title_expectation()) :: Expect.t()
  @spec page_to_have_title(Fluffy.Page.title_expectation(), [page_to_have_title_option()]) :: Expect.t()
  def page_to_have_title(expected, options \\ [])
      when (is_binary(expected) or is_struct(expected, Regex)) and is_list(options) do
    native_expectation(:page_to_have_title, :page, :title, expected, options)
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

  #{NimbleOptions.docs(Options.expectation_schema(:page_to_have_url))}
  """
  @spec page_to_have_url(Fluffy.Page.url_expectation()) :: Expect.t()
  @spec page_to_have_url(Fluffy.Page.url_expectation(), [page_to_have_url_option()]) :: Expect.t()
  def page_to_have_url(expected, options \\ [])

  def page_to_have_url(expected, options)
      when (is_binary(expected) or is_struct(expected, Regex) or is_function(expected, 1)) and is_list(options) do
    options = Options.validate_expectation!(:page_to_have_url, options)
    {ignore_case, options} = Keyword.pop(options, :ignore_case)
    Internal.new(:page, :url, URLMatcher.ignore_case(expected, ignore_case), options)
  end

  def page_to_have_url(components, options) when is_list(components) and is_list(options) do
    options = Options.validate_expectation!(:page_to_have_url, options)
    {ignore_case, options} = Keyword.pop(options, :ignore_case)
    if ignore_case, do: raise(ArgumentError, "ignore_case: requires a string or regular expression URL")
    Internal.new(:page, :url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc "Expects the active page to have the given opener handle, or no opener with `nil`."
  @spec page_to_have_opener(Fluffy.Page.t() | nil, [Expect.option()]) :: Expect.t()
  def page_to_have_opener(expected, options \\ [])
      when (is_struct(expected, Fluffy.Page) or is_nil(expected)) and is_list(options) do
    Internal.new(:page, :opener, expected, options)
  end

  defp expect_active_page(%Session{} = session, %Expect{kind: :url} = expectation) do
    Fluffy.__expect__(session, expectation)
  end

  defp expect_active_page(%Session{} = session, %Expect{kind: :title} = expectation) do
    Fluffy.__expect__(session, expectation)
  end

  defp expect_active_page(%Session{} = session, %Expect{kind: :opener} = expectation) do
    actual = session |> Session.handle() |> Fluffy.Page.opener()
    assert_expected!(expectation, actual)
    session
  end

  defp expect_active_page(_session, %Expect{} = expectation) do
    raise ArgumentError, "unsupported active page expectation: #{Internal.describe(expectation)}"
  end

  defp assert_expected!(%Expect{} = expectation, actual) do
    assert_expectation_truth!(expectation, Internal.matches?(expectation.expected, actual), actual)
  end

  defp assert_expectation_truth!(%Expect{} = expectation, passed?, actual) do
    if passed? == expectation.negated? do
      raise ExUnit.AssertionError,
        message: "Expected #{Internal.describe(expectation)}, got #{inspect(actual)}"
    end

    :ok
  end

  defp normalize_expectation(%Expect{target: :page, kind: :url, expected: expected} = expectation, session)
       when is_binary(expected) do
    %{expectation | expected: Fluffy.Backend.absolute_url(session, expected)}
  end

  defp normalize_expectation(
         %Expect{target: :page, kind: :url, expected: {:ignore_case, expected}} = expectation,
         session
       ) do
    %{expectation | expected: {:ignore_case, Fluffy.Backend.absolute_url(session, expected)}}
  end

  defp normalize_expectation(%Expect{} = expectation, _session), do: expectation
end
