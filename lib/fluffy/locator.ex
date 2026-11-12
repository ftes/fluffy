defmodule Fluffy.Locator do
  @moduledoc """
  A lazy, driver-independent element query.

      by_css("#potions")
      |> by_role(:row)
      |> filter(has_text: "Polyjuice Potion")
      |> by_role(:button, name: "Inspect")

  Options marked *Playwright only.* compile into the browser selector. Static and
  LiveView sessions raise `Fluffy.CapabilityError` when they resolve a locator that
  uses one.

  A regular expression in `name:`, `has_text:` or `has_not_text:` is a JavaScript
  `RegExp` on every driver: a `Regex` becomes one with `PlaywrightEx.RegExp.new/1`,
  which raises `ArgumentError` on PCRE-only syntax, or pass a `PlaywrightEx.RegExp`.

  Role locators accept these options:

  #{NimbleOptions.docs(Fluffy.Options.role_locator_schema())}

  Text, label, placeholder, alternative-text, and title locators accept:

  #{NimbleOptions.docs(Fluffy.Options.exact_locator_schema())}

  `filter/2` accepts:

  #{NimbleOptions.docs(Fluffy.Options.filter_locator_schema())}
  """
  @moduledoc groups: ["Constructors", "Refinement", "Frames"]

  alias Fluffy.FrameLocator
  alias Fluffy.Locator.Internal
  alias Fluffy.Options

  @enforce_keys [:operations]
  defstruct operations: []

  @type t :: %__MODULE__{operations: [term()]}
  @type scope :: t() | FrameLocator.t()
  @type role_option :: unquote(NimbleOptions.option_typespec(Options.role_locator_schema()))
  @type exact_option :: unquote(NimbleOptions.option_typespec(Options.exact_locator_schema()))
  @type filter_option :: unquote(NimbleOptions.option_typespec(Options.filter_locator_schema()))

  @doc group: "Constructors"
  @doc """
  Matches elements by ARIA role, narrowed by accessible name and the role options in the
  module docs.

  Pass a locator or frame scope first, as `by_role(parent, role)`, to match inside it.
  `by_role/3` does the same and also takes options.

      session |> click(by_role(:button, name: "Brew potion"))

      by_css("#potions") |> by_role(:row, name: "Polyjuice Potion")

  The Phoenix backend knows the implicit roles `article`, `banner`, `blockquote`, `button`,
  `caption`, `cell`, `checkbox`, `code`, `columnheader`, `combobox`, `complementary`,
  `contentinfo`, `definition`, `deletion`, `dialog`, `document`, `emphasis`, `figure`, `form`,
  `gridcell`, `group`, `heading`, `img`, `insertion`, `link`, `list`, `listbox`, `listitem`,
  `main`, `mark`, `math`, `meter`, `navigation`, `option`, `paragraph`, `presentation`,
  `progressbar`, `radio`, `region`, `row`, `rowgroup`, `rowheader`, `search`, `searchbox`,
  `separator`, `slider`, `spinbutton`, `status`, `strong`, `subscript`, `superscript`, `table`,
  `term`, `textbox` and `time`; any other role needs an explicit `role` attribute there.
  """
  @spec by_role(atom(), [role_option()]) :: t()
  @spec by_role(scope(), atom()) :: t()
  @spec by_role(scope(), atom(), [role_option()]) :: t()
  def by_role(role, options \\ [])

  def by_role(role, options) when is_atom(role) and is_list(options) do
    Internal.new({:role, role, Options.validate_role_locator!(options)})
  end

  def by_role(parent, role) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_role(parent, role, [])
  end

  @doc group: "Constructors"
  @doc "Like `by_role/2`, inside `parent`, a locator or frame scope, with options."
  def by_role(parent, role, options)
      when (is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator)) and is_atom(role) and is_list(options) do
    child_query(parent, {:role, role, Options.validate_role_locator!(options)})
  end

  @doc group: "Constructors"
  @doc """
  Matches elements by their text, as a normalized case-insensitive substring unless `exact: true`.

  Pass a locator or frame scope first to match inside it; `by_text/3` also takes options.
  """
  @spec by_text(String.t(), [exact_option()]) :: t()
  @spec by_text(scope(), String.t()) :: t()
  @spec by_text(scope(), String.t(), [exact_option()]) :: t()
  def by_text(text, options \\ [])

  def by_text(text, options) when is_binary(text) and is_list(options) do
    Internal.new({:text, text, Options.validate_exact_locator!(options)})
  end

  def by_text(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_text(parent, text, [])
  end

  @doc group: "Constructors"
  @doc "Like `by_text/2`, inside `parent`, a locator or frame scope, with options."
  def by_text(parent, text, options) when is_binary(text) and is_list(options) do
    child_query(parent, {:text, text, Options.validate_exact_locator!(options)})
  end

  @doc group: "Constructors"
  @doc """
  Matches form controls by their label, as a normalized case-insensitive substring unless `exact: true`.

  Pass a locator or frame scope first to match inside it; `by_label/3` also takes options.
  """
  @spec by_label(String.t(), [exact_option()]) :: t()
  @spec by_label(scope(), String.t()) :: t()
  @spec by_label(scope(), String.t(), [exact_option()]) :: t()
  def by_label(text, options \\ [])

  def by_label(text, options) when is_binary(text) and is_list(options) do
    attribute_or_label_locator(:label, text, options)
  end

  def by_label(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_label(parent, text, [])
  end

  @doc group: "Constructors"
  @doc "Like `by_label/2`, inside `parent`, a locator or frame scope, with options."
  def by_label(parent, text, options) when is_binary(text) and is_list(options) do
    child_query(parent, {:label, text, Options.validate_exact_locator!(options)})
  end

  @doc group: "Constructors"
  @doc """
  Matches elements by their `placeholder` attribute, as a case-insensitive substring unless `exact: true`.

  Pass a locator or frame scope first to match inside it; `by_placeholder/3` also takes options.
  """
  @spec by_placeholder(String.t(), [exact_option()]) :: t()
  @spec by_placeholder(scope(), String.t()) :: t()
  @spec by_placeholder(scope(), String.t(), [exact_option()]) :: t()
  def by_placeholder(text, options \\ [])

  def by_placeholder(text, options) when is_binary(text) and is_list(options) do
    attribute_locator("placeholder", text, options)
  end

  def by_placeholder(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_placeholder(parent, text, [])
  end

  @doc group: "Constructors"
  @doc "Like `by_placeholder/2`, inside `parent`, a locator or frame scope, with options."
  def by_placeholder(parent, text, options) when is_binary(text) and is_list(options) do
    append_attribute_locator(parent, "placeholder", text, options)
  end

  @doc group: "Constructors"
  @doc """
  Matches elements by their `alt` attribute, as a case-insensitive substring unless `exact: true`.

  Pass a locator or frame scope first to match inside it; `by_alt_text/3` also takes options.
  """
  @spec by_alt_text(String.t(), [exact_option()]) :: t()
  @spec by_alt_text(scope(), String.t()) :: t()
  @spec by_alt_text(scope(), String.t(), [exact_option()]) :: t()
  def by_alt_text(text, options \\ [])

  def by_alt_text(text, options) when is_binary(text) and is_list(options) do
    attribute_locator("alt", text, options)
  end

  def by_alt_text(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_alt_text(parent, text, [])
  end

  @doc group: "Constructors"
  @doc "Like `by_alt_text/2`, inside `parent`, a locator or frame scope, with options."
  def by_alt_text(parent, text, options) when is_binary(text) and is_list(options) do
    append_attribute_locator(parent, "alt", text, options)
  end

  @doc group: "Constructors"
  @doc """
  Matches elements by their `title` attribute, as a case-insensitive substring unless `exact: true`.

  Pass a locator or frame scope first to match inside it; `by_title/3` also takes options.
  """
  @spec by_title(String.t(), [exact_option()]) :: t()
  @spec by_title(scope(), String.t()) :: t()
  @spec by_title(scope(), String.t(), [exact_option()]) :: t()
  def by_title(text, options \\ [])

  def by_title(text, options) when is_binary(text) and is_list(options) do
    attribute_locator("title", text, options)
  end

  def by_title(parent, text) when is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator) do
    by_title(parent, text, [])
  end

  @doc group: "Constructors"
  @doc "Like `by_title/2`, inside `parent`, a locator or frame scope, with options."
  def by_title(parent, text, options) when is_binary(text) and is_list(options) do
    append_attribute_locator(parent, "title", text, options)
  end

  @doc group: "Constructors"
  @doc """
  Matches elements whose test id equals `test_id`, as Playwright's `getByTestId`.

  The attribute is Playwright Test's `testIdAttribute`, on every driver:
  `config :playwright_ex, :test, test_id_attribute: "data-owl"`, `data-testid` by default.
  For another attribute in one place, use `by_css("[data-owl=\\"hedwig\\"]")`.

  Pass a locator or frame scope first to match inside it.

      by_test_id("hedwig")
      by_css("#owlery") |> by_test_id("hedwig")
  """
  @spec by_test_id(String.t()) :: t()
  def by_test_id(test_id) when is_binary(test_id), do: Internal.new({:test_id, test_id})

  @doc group: "Constructors"
  @doc "Like `by_test_id/1`, inside `parent`, a locator or frame scope."
  @spec by_test_id(scope(), String.t()) :: t()
  @spec by_test_id(String.t(), keyword()) :: no_return()
  def by_test_id(parent, test_id)
      when is_binary(test_id) and (is_struct(parent, __MODULE__) or is_struct(parent, FrameLocator)),
      do: child_query(parent, {:test_id, test_id})

  def by_test_id(test_id, options) when is_binary(test_id) and is_list(options) do
    raise ArgumentError,
          "by_test_id/2 takes no options, as Playwright's getByTestId: set the attribute with " <>
            ~s{`config :playwright_ex, :test, test_id_attribute: ...`, or use by_css("[data-owl=\\"hedwig\\"]"), } <>
            "got: #{inspect(options)}"
  end

  @doc group: "Constructors"
  @doc "Matches elements by a CSS selector, which must be valid browser CSS."
  @spec by_css(String.t()) :: t()
  def by_css(css) when is_binary(css), do: Internal.new({:css, css})

  @doc group: "Constructors"
  @doc "Like `by_css/1`, inside `parent`, a locator or frame scope."
  @spec by_css(scope(), String.t()) :: t()
  def by_css(parent, css) when is_binary(css) do
    child_query(parent, {:css, css})
  end

  @doc group: "Frames"
  @doc "Creates a lazy frame scope. Frame traversal requires the Playwright driver."
  @doc playwright_only: true
  @spec frame_locator(String.t()) :: FrameLocator.t()
  def frame_locator(css) when is_binary(css), do: css |> by_css() |> content_frame()

  @doc group: "Frames"
  @doc "Creates a nested frame scope relative to an element or frame query."
  @doc playwright_only: true
  @spec frame_locator(scope(), String.t()) :: FrameLocator.t()
  def frame_locator(parent, css) when is_binary(css), do: parent |> by_css(css) |> content_frame()

  @doc group: "Frames"
  @doc "Converts an iframe element query to a lazy query of its content frame."
  @doc playwright_only: true
  @spec content_frame(t()) :: FrameLocator.t()
  def content_frame(%__MODULE__{} = owner), do: %FrameLocator{owner: owner}

  defp child_query(%__MODULE__{} = parent, operation), do: Internal.append(parent, operation)

  defp child_query(%FrameLocator{owner: owner}, operation) do
    owner |> Internal.append(:enter_frame) |> Internal.append(operation)
  end

  @doc group: "Refinement"
  @doc """
  Matches only elements matched by both locators, preserving the left locator's order.

  The right locator resolves from the same query root, not within each left match.
  Inside `filter/2`'s `:has` or `:has_not`, that root is the filter candidate.

      by_css("#email") |> and_(by_label("Email", exact: true))

  With Playwright, the right locator may be relative to the left locator's frame
  or use the same frame prefix. Playwright validates frame compatibility when
  the locator resolves; intersections across different frames are unsupported.

      frame = frame_locator("#gringotts")
      by_css(frame, "input") |> and_(by_label(frame, "Email"))

  Like other locators, intersections are lazy and retain normal action strictness.
  """
  @spec and_(t(), t()) :: t()
  def and_(%__MODULE__{} = left, %__MODULE__{} = right) do
    Internal.append(left, {:and, right})
  end

  @doc group: "Refinement"
  @doc """
  Matches elements in either locator, once each in document order, retaining action strictness.

      by_role(:button, name: "Accio") |> or_(by_role(:link, name: "Accio"))
  """
  @spec or_(t(), t()) :: t()
  def or_(%__MODULE__{} = left, %__MODULE__{} = right), do: Internal.append(left, {:or, right})

  @doc group: "Refinement"
  @doc """
  Keeps the matches that satisfy every option. The module docs list the options.

      by_role(:row) |> filter(has_text: "Polyjuice Potion", has: by_role(:button, name: "Inspect"))
  """
  @spec filter(t(), [filter_option()]) :: t()
  def filter(%__MODULE__{} = locator, options) when is_list(options) do
    Internal.append(
      locator,
      {:filter, Options.validate_filter_locator!(options)}
    )
  end

  @doc group: "Refinement"
  @doc "Narrows to the first match."
  def first(%__MODULE__{} = locator), do: Internal.append(locator, {:nth, 0})

  @doc group: "Refinement"
  @doc "Narrows to the last match."
  def last(%__MODULE__{} = locator), do: Internal.append(locator, {:nth, -1})

  @doc group: "Refinement"
  @doc "Narrows to the match at the zero-based `index`."
  def nth(%__MODULE__{} = locator, index) when is_integer(index) do
    Internal.append(locator, {:nth, index})
  end

  @doc group: "Refinement"
  @doc """
  Returns a locator matching `locator`'s elements inside each element matched by `other`.

  Relative operations such as `nth/2` and `first/1` on `locator` are resolved
  separately inside each match of `other`, so this picks the third cell of every row,
  not the third cell of the table:

      by_css("td") |> nth(2) |> within(by_css("tr"))

  Static and LiveView resolve it the same way. Compare scoping by the parent locator,
  as in `by_css(row, "td")`, where `nth/2` picks from all the matches together.
  """
  @spec within(t(), t()) :: t()
  def within(%__MODULE__{} = locator, %__MODULE__{} = other), do: Internal.new({:within, other, locator})

  defp attribute_or_label_locator(:label, text, options) do
    Internal.new({:label, text, Options.validate_exact_locator!(options)})
  end

  defp attribute_locator(attribute, text, options) do
    Internal.new({:attribute, attribute, text, Options.validate_exact_locator!(options)})
  end

  defp append_attribute_locator(parent, attribute, text, options) do
    child_query(
      parent,
      {:attribute, attribute, text, Options.validate_exact_locator!(options)}
    )
  end
end

defimpl Inspect, for: Fluffy.Locator do
  import Inspect.Algebra

  def inspect(locator, _options) do
    concat(["#Fluffy.Locator<", Fluffy.Locator.Internal.describe(locator), ">"])
  end
end
