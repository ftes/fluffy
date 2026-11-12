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
  @moduledoc groups: ["Running expectations", "Locator assertions", "Page assertions", "Events"]

  alias Fluffy.Expect
  alias Fluffy.Expect.Internal
  alias Fluffy.Locator
  alias Fluffy.Options
  alias Fluffy.Session

  @enforce_keys [:target, :kind]
  defstruct [:target, :kind, :expected, options: [], negated?: false]

  @dialyzer {:nowarn_function, expect: 3}

  # An Elixir `Regex` is converted to the `PlaywrightEx.RegExp` it stands for (`text_values!/1`).
  defguardp is_text(value) when is_binary(value) or is_struct(value, Regex) or is_struct(value, PlaywrightEx.RegExp)

  @type target :: {:locator, Locator.t()} | :page

  @type kind ::
          :accessible_description
          | :accessible_error_message
          | :accessible_name
          | :aria_snapshot
          | :attached
          | :attribute
          | :checked
          | :class
          | :contain_class
          | :contain_text
          | :count
          | :css
          | :disabled
          | :editable
          | :empty
          | :enabled
          | :focused
          | :hidden
          | :id
          | :in_viewport
          | :js_property
          | :opener
          | :role
          | :screenshot
          | :text
          | :title
          | :url
          | :value
          | :values
          | :visible

  @type text_expectation :: String.t() | Regex.t() | PlaywrightEx.RegExp.t()

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
  @type to_have_css_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_css)))
  @type to_have_js_property_option ::
          unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_js_property)))
  @type to_have_screenshot_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:to_have_screenshot)))
  @type to_have_role_option :: unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_role)))
  @type to_have_accessible_name_option ::
          unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_accessible_name)))
  @type to_have_accessible_description_option ::
          unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_accessible_description)))
  @type to_have_accessible_error_message_option ::
          unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_have_accessible_error_message)))
  @type to_match_aria_snapshot_option ::
          unquote(NimbleOptions.option_typespec(Options.expectation_schema(:to_match_aria_snapshot)))
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

  @doc group: "Running expectations"
  @doc "Executes an expectation and returns the unchanged or reconciled session."
  @spec expect(Session.t(), t(), [option()]) :: Session.t()
  def expect(%Session{} = session, %Expect{} = expectation, options \\ []) do
    expectation =
      Internal.merge_options(expectation, options)

    case expectation.target do
      {:locator, _locator} ->
        Fluffy.__expect__(session, expectation)

      :page ->
        expect_active_page(session, expectation)
    end
  end

  @doc group: "Events"
  @doc """
  Registers before the action, awaits a matching event, and optionally asserts on
  its value. Action and assertion callbacks run once in the caller; their return
  values are ignored. Returns the input session, retaining its page selection.
  """
  def expect_event(session, event, action), do: Fluffy.Event.expect(session, event, action, nil, [])

  @doc group: "Events"
  @doc "Expects an event with an assertion callback or wait options."
  def expect_event(session, event, action, assertion) when is_function(assertion, 1),
    do: Fluffy.Event.expect(session, event, action, assertion, [])

  def expect_event(session, event, action, options) when is_list(options),
    do: Fluffy.Event.expect(session, event, action, nil, options)

  @doc group: "Events"
  @doc "Expects an event with an assertion callback and wait options."
  def expect_event(session, event, action, assertion, options) when is_function(assertion, 1) and is_list(options),
    do: Fluffy.Event.expect(session, event, action, assertion, options)

  @doc group: "Running expectations"
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
    {timeout, matching} = Options.split_expectation!(:to_be_in_viewport, options)
    Internal.new({:locator, locator}, :in_viewport, matching, timeout)
  end

  @doc group: "Locator assertions"
  @doc playwright_only: true
  @doc """
  Asserts a computed CSS property of the target, equal to a string or matching a regular
  expression. Requires Playwright, including when negated.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_css))}
  """
  @spec to_have_css(Locator.t(), String.t(), text_expectation(), [to_have_css_option()]) :: t()
  def to_have_css(%Locator{} = locator, name, value, options \\ []) when is_binary(name) and is_text(value) do
    {timeout, matching} = Options.split_expectation!(:to_have_css, options)
    Internal.new({:locator, locator}, :css, {name, text_values!(value), matching}, timeout)
  end

  @doc group: "Locator assertions"
  @doc playwright_only: true
  @doc """
  Asserts a JavaScript property of the target element, which can be a primitive or a
  plain serializable object. Requires Playwright, including when negated.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_js_property))}
  """
  @spec to_have_js_property(Locator.t(), String.t(), term(), [to_have_js_property_option()]) :: t()
  def to_have_js_property(%Locator{} = locator, name, value, options \\ []) when is_binary(name) do
    native_expectation(:to_have_js_property, {:locator, locator}, :js_property, {name, value}, options)
  end

  @doc group: "Locator assertions"
  @doc playwright_only: true
  @doc """
  Asserts that a screenshot of the target matches a baseline image, a `.png` or `.webp`
  file. Requires Playwright, including when negated.

      expect(session, to_have_screenshot(by_role(:main), name: "main.png"))

  In a module with `use Fluffy.Test`, `PlaywrightEx.Test` resolves `name:` (or, without
  one, the test's name) to a file, as Playwright does; see "Snapshots" in its docs. A
  missing baseline is written there and fails the test at the end of its body, as in
  Playwright. A mismatch writes `-actual`, `-diff` and `-previous` images to the test's
  output dir. `path:` names the file itself instead, relative to the current working
  directory; elsewhere it is required. Commit the baselines.

  `config :playwright_ex, :expect` sets `update_snapshots:`, where `:none` fails on a
  missing baseline, `:missing` writes it and passes, and `:changed` or `:all` rewrite a
  mismatching one, and comparison defaults such as `to_have_screenshot: %{maxDiffPixels: 10}`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:to_have_screenshot)}.

  #{NimbleOptions.docs(Options.action_schema(:to_have_screenshot))}
  """
  @spec to_have_screenshot(Locator.t(), [to_have_screenshot_option()]) :: t()
  def to_have_screenshot(%Locator{} = locator, options \\ []), do: screenshot_expectation({:locator, locator}, options)

  defp screenshot_expectation(target, options) do
    {timeout, native} = Options.split_action!(:to_have_screenshot, options)
    Internal.new(target, :screenshot, native, timeout)
  end

  @doc group: "Locator assertions"
  @doc """
  Asserts the target's ARIA role, such as `:button`. Static and LiveView compute it
  from markup, as for `Fluffy.Locator.by_role/2`.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_role))}
  """
  @spec to_have_role(Locator.t(), atom(), [to_have_role_option()]) :: t()
  def to_have_role(%Locator{} = locator, role, options \\ []) when is_atom(role) do
    native_expectation(:to_have_role, {:locator, locator}, :role, role, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Asserts the target's accessible name, equal to a string or matching a regular
  expression. Static and LiveView compute it from markup, as for `Fluffy.Locator.by_role/2`.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_accessible_name))}
  """
  @spec to_have_accessible_name(Locator.t(), text_expectation(), [to_have_accessible_name_option()]) :: t()
  def to_have_accessible_name(%Locator{} = locator, expected, options \\ []) when is_text(expected) do
    text_expectation(:to_have_accessible_name, locator, :accessible_name, expected, options)
  end

  @doc group: "Locator assertions"
  @doc """
  Asserts the target's accessible description, equal to a string or matching a regular
  expression. Static and LiveView compute it from markup, as for `Fluffy.Locator.by_role/2`.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_accessible_description))}
  """
  @spec to_have_accessible_description(Locator.t(), text_expectation(), [to_have_accessible_description_option()]) :: t()
  def to_have_accessible_description(%Locator{} = locator, expected, options \\ []) when is_text(expected) do
    text_expectation(:to_have_accessible_description, locator, :accessible_description, expected, options)
  end

  @doc group: "Locator assertions"
  @doc playwright_only: true
  @doc """
  Asserts the target's accessible error message, equal to a string or matching a regular
  expression. Requires Playwright, including when negated.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_have_accessible_error_message))}
  """
  @spec to_have_accessible_error_message(Locator.t(), text_expectation(), [to_have_accessible_error_message_option()]) ::
          t()
  def to_have_accessible_error_message(%Locator{} = locator, expected, options \\ []) when is_text(expected) do
    text_expectation(:to_have_accessible_error_message, locator, :accessible_error_message, expected, options)
  end

  @doc group: "Locator assertions"
  @doc playwright_only: true
  @doc """
  Asserts the target's ARIA snapshot against `expected`, the snapshot as YAML text, or
  against a snapshot file in its place. Requires Playwright, including when negated.

      expect(session, to_match_aria_snapshot(by_css("body"), name: "body.aria.yml"))

  An empty `expected` fails with the current snapshot in its message, to paste in.

  The file is found as a screenshot baseline is (see `to_have_screenshot/2`): `name:`, or
  the test's name, resolved by `PlaywrightEx.Test` in a module with `use Fluffy.Test`, or
  `path:`, relative to the current working directory. A missing file is written and fails
  the test at its end, or passes under `update_snapshots: :missing`; negated, it fails.
  Under `:none` a missing file fails, comparing against an empty snapshot. Negated, a
  missing file passes under `:none`, `:all` or `:changed`.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_match_aria_snapshot))}
  """
  @spec to_match_aria_snapshot(Locator.t(), String.t() | [to_match_aria_snapshot_option()], [
          to_match_aria_snapshot_option()
        ]) :: t()
  def to_match_aria_snapshot(%Locator{} = locator, expected_or_options, options \\ [])
      when is_binary(expected_or_options) or is_list(expected_or_options) do
    aria_snapshot_expectation({:locator, locator}, expected_or_options, options)
  end

  # The file travels with the expected value, for PlaywrightEx to raise if both are given.
  defp aria_snapshot_expectation(target, options, []) when is_list(options),
    do: aria_snapshot_expectation(target, nil, options)

  defp aria_snapshot_expectation(target, expected, options) when is_binary(expected) or is_nil(expected) do
    {timeout, file} = Options.split_expectation!(:to_match_aria_snapshot, options)
    Internal.new(target, :aria_snapshot, {expected, file}, timeout)
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
    {timeout, state} = Options.split_expectation!(:to_be_checked, options)
    checked = Keyword.get(state, :checked, :unset)
    indeterminate = Keyword.get(state, :indeterminate, :unset)

    if indeterminate == true and checked != :unset do
      raise ArgumentError, "checked: and indeterminate: true cannot be used together"
    end

    expected =
      cond do
        indeterminate == true -> :indeterminate
        checked == false -> :unchecked
        true -> :checked
      end

    Internal.new({:locator, locator}, :checked, expected, timeout)
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
  Expects the selected values of a multi-select. As in Playwright, it fails on
  any other element, a single select included; use `to_have_value/3` there.

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
  def to_have_text(%Locator{} = locator, expected, options \\ []) when is_text(expected) or is_list(expected) do
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
  def to_contain_text(%Locator{} = locator, expected, options \\ []) when is_text(expected) or is_list(expected) do
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
      when is_binary(name) and (is_nil(value) or is_text(value)) and is_list(options) do
    {timeout, matching} = Options.split_expectation!(:to_have_attribute, options)
    Internal.new({:locator, locator}, :attribute, {name, text_values!(value), matching}, timeout)
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
  def to_have_class(%Locator{} = locator, expected, options \\ []) when is_text(expected) or is_list(expected) do
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
  def to_have_id(%Locator{} = locator, expected, options \\ []) when is_text(expected) do
    native_expectation(:to_have_id, {:locator, locator}, :id, text_values!(expected), options)
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
  [Visibility and DOM presence](assertions.md#visibility-and-dom-presence).

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
    {timeout, state} = Options.split_expectation!(matcher, options)
    expectation = Internal.new({:locator, locator}, kind, true, timeout)
    if Keyword.get(state, kind, true), do: expectation, else: Internal.negate(expectation)
  end

  defp native_expectation(matcher, target, kind, expected, options),
    do: Internal.new(target, kind, expected, Options.validate_expectation!(matcher, options))

  # The options that select how text is read and compared travel with the expected value.
  defp text_expectation(matcher, locator, kind, expected, options) do
    {timeout, matching} = Options.split_expectation!(matcher, options)
    Internal.new({:locator, locator}, kind, {text_values!(expected), matching}, timeout)
  end

  defp text_values!(expected) when is_list(expected) do
    if Enum.all?(expected, &is_text(&1)) do
      Enum.map(expected, &Internal.reg_exp/1)
    else
      raise ArgumentError, "expected a list of strings or regular expressions, got: #{inspect(expected)}"
    end
  end

  defp text_values!(expected), do: Internal.reg_exp(expected)

  @doc group: "Page assertions"
  @doc """
  Expects the active page title to equal a string or match a regular expression.

  Like Playwright's `toHaveTitle`, the assertion retries on Live and Playwright
  pages and normalizes whitespace before matching.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:page_to_have_title))}
  """
  @spec page_to_have_title(Fluffy.Page.title_expectation()) :: Expect.t()
  @spec page_to_have_title(Fluffy.Page.title_expectation(), [page_to_have_title_option()]) :: Expect.t()
  def page_to_have_title(expected, options \\ []) when is_text(expected) and is_list(options) do
    native_expectation(:page_to_have_title, :page, :title, text_values!(expected), options)
  end

  @doc group: "Page assertions"
  @doc """
  Expects the active page to have the requested URL, as Playwright's `toHaveURL`.

  A string is resolved against the session's base URL and must equal the complete URL,
  query and fragment included. A regular expression matches the URL, and a function gets the
  URL string and returns whether it matches. Keep predicates quick and nonblocking.

      expect(session, page_to_have_url("/creatures/fluffy"))
      expect(session, page_to_have_url(~r{/creatures/[a-z]+$}))
      expect(session, page_to_have_url(&(URI.parse(&1).path == "/creatures")))

  ## Assertion options

  #{NimbleOptions.docs(Options.expectation_schema(:page_to_have_url))}
  """
  @spec page_to_have_url(Fluffy.Page.url_expectation()) :: Expect.t()
  @spec page_to_have_url(Fluffy.Page.url_expectation(), [page_to_have_url_option()]) :: Expect.t()
  def page_to_have_url(expected, options \\ [])

  def page_to_have_url(expected, options) when (is_text(expected) or is_function(expected, 1)) and is_list(options) do
    {timeout, matching} = Options.split_expectation!(:page_to_have_url, options)
    Internal.new(:page, :url, {Internal.reg_exp(expected), matching}, timeout)
  end

  @doc group: "Page assertions"
  @doc playwright_only: true
  @doc """
  Asserts that a screenshot of the active page matches a baseline image, like
  `to_have_screenshot/2`, which also says where baselines go.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:to_have_screenshot)}.

  #{NimbleOptions.docs(Options.action_schema(:to_have_screenshot))}
  """
  @spec page_to_have_screenshot([to_have_screenshot_option()]) :: Expect.t()
  def page_to_have_screenshot(options \\ []) when is_list(options), do: screenshot_expectation(:page, options)

  @doc group: "Page assertions"
  @doc playwright_only: true
  @doc """
  Asserts the active page's ARIA snapshot against `expected`, or a snapshot file in its
  place, like `to_match_aria_snapshot/3`, which also says how a missing file behaves.

  ## Options

  #{NimbleOptions.docs(Options.expectation_schema(:to_match_aria_snapshot))}
  """
  @spec page_to_match_aria_snapshot(String.t() | [to_match_aria_snapshot_option()], [
          to_match_aria_snapshot_option()
        ]) :: Expect.t()
  def page_to_match_aria_snapshot(expected_or_options, options \\ [])
      when (is_binary(expected_or_options) or is_list(expected_or_options)) and is_list(options) do
    aria_snapshot_expectation(:page, expected_or_options, options)
  end

  @doc group: "Page assertions"
  @doc "Expects the active page to have the given opener handle, or no opener with `nil`."
  @spec page_to_have_opener(Fluffy.Page.t() | nil, [Expect.option()]) :: Expect.t()
  def page_to_have_opener(expected, options \\ [])
      when (is_struct(expected, Fluffy.Page) or is_nil(expected)) and is_list(options) do
    Internal.new(:page, :opener, expected, options)
  end

  defp expect_active_page(%Session{} = session, %Expect{kind: kind} = expectation)
       when kind in [:url, :title, :screenshot, :aria_snapshot] do
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
end
