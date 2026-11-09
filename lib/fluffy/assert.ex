defmodule Fluffy.Assert do
  @moduledoc """
  ExUnit-style assertions backed by `Fluffy.Expect`.

  Use this module after `use ExUnit.Case` (or your application's case module)
  to replace the conflicting ExUnit imports:

      use ExUnit.Case
      use Fluffy.Assert

      import Fluffy
      import Fluffy.Locator

  Inside a test with an initialized session:

      session
      |> assert(visible(by_text("Creature registered")))
      |> refute(page_title("Error"))

  Locator constructors take a locator. Page constructors target the active page.
  All constructors return `Fluffy.Expect` values, not booleans.

  Ordinary ExUnit assertions, including custom messages and pattern matching,
  retain ExUnit semantics. With a typed expectation as the second argument,
  `assert/2` executes it and `refute/2` executes its negation. Both return the
  updated session. A third argument supplies expectation options.

  Negation retains the driver's retry and missing-element semantics. Refuting
  visibility accepts an absent or hidden element; use `count(locator, 0)` for
  absence. Static and Live drivers check structural visibility, while Playwright
  checks rendered visibility. Refutation does not turn driver errors into success.
  """
  @moduledoc groups: ["Running expectations", "Locator assertions", "Page assertions", "Events"]

  @doc group: "Running expectations"
  @doc "Imports the assertion vocabulary without conflicts with ExUnit."
  defmacro __using__(_options) do
    quote do
      import ExUnit.Assertions, except: [assert: 2, refute: 2]
      import Fluffy.Assert
    end
  end

  @doc group: "Running expectations"
  @doc "Executes a typed expectation, or delegates an ordinary assertion with a message to ExUnit."
  @spec assert(Fluffy.Session.t(), Fluffy.Expect.t()) :: Fluffy.Session.t()
  @spec assert(term(), String.t() | keyword()) :: true
  def assert(session, %Fluffy.Expect{} = expectation), do: Fluffy.Expect.expect(session, expectation)
  def assert(expression, message), do: ExUnit.Assertions.assert(expression, message)

  @doc group: "Running expectations"
  @doc "Executes a negated expectation, or delegates an ordinary refutation with a message to ExUnit."
  @spec refute(Fluffy.Session.t(), Fluffy.Expect.t()) :: Fluffy.Session.t()
  @spec refute(term(), String.t() | keyword()) :: false
  def refute(session, %Fluffy.Expect{} = expectation), do: Fluffy.Expect.expect(session, Fluffy.Expect.not_(expectation))

  def refute(expression, message), do: ExUnit.Assertions.refute(expression, message)

  @doc group: "Running expectations"
  @doc "Executes a typed expectation with additional options."
  @spec assert(Fluffy.Session.t(), Fluffy.Expect.t(), [Fluffy.Expect.option()]) :: Fluffy.Session.t()
  def assert(session, %Fluffy.Expect{} = expectation, options), do: Fluffy.Expect.expect(session, expectation, options)

  @doc group: "Running expectations"
  @doc "Executes a negated expectation with additional options."
  @spec refute(Fluffy.Session.t(), Fluffy.Expect.t(), [Fluffy.Expect.option()]) :: Fluffy.Session.t()
  def refute(session, %Fluffy.Expect{} = expectation, options),
    do: Fluffy.Expect.expect(session, Fluffy.Expect.not_(expectation), options)

  @doc group: "Running expectations"
  @doc """
  Asserts that the locator resolves to a visible element and returns the session.

  Equivalent to `assert(session, visible(locator), options)`.
  For DOM presence regardless of visibility, use a `count` expectation.
  """
  @spec assert_has(Fluffy.Session.t(), Fluffy.Locator.t(), [Fluffy.Expect.option()]) :: Fluffy.Session.t()
  def assert_has(session, %Fluffy.Locator{} = locator, options \\ []), do: assert(session, visible(locator), options)

  @doc group: "Running expectations"
  @doc """
  Asserts that the locator is absent or hidden and returns the session.

  Equivalent to `refute(session, visible(locator), options)`.
  Use `count(locator, 0)` to require DOM absence.
  """
  @spec refute_has(Fluffy.Session.t(), Fluffy.Locator.t(), [Fluffy.Expect.option()]) :: Fluffy.Session.t()
  def refute_has(session, %Fluffy.Locator{} = locator, options \\ []), do: refute(session, visible(locator), options)

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_have_count/3`."
  @spec count(Fluffy.Locator.t(), non_neg_integer(), [Fluffy.Expect.to_have_count_option()]) :: Fluffy.Expect.t()
  defdelegate count(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_have_count

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_be_visible/2`."
  @spec visible(Fluffy.Locator.t(), [Fluffy.Expect.to_be_visible_option()]) :: Fluffy.Expect.t()
  defdelegate visible(locator, options \\ []), to: Fluffy.Expect, as: :to_be_visible

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_be_disabled/2`."
  @spec disabled(Fluffy.Locator.t(), [Fluffy.Expect.to_be_disabled_option()]) :: Fluffy.Expect.t()
  defdelegate disabled(locator, options \\ []), to: Fluffy.Expect, as: :to_be_disabled

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_be_editable/2`."
  @spec editable(Fluffy.Locator.t(), [Fluffy.Expect.to_be_editable_option()]) :: Fluffy.Expect.t()
  defdelegate editable(locator, options \\ []), to: Fluffy.Expect, as: :to_be_editable

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_be_enabled/2`."
  @spec enabled(Fluffy.Locator.t(), [Fluffy.Expect.to_be_enabled_option()]) :: Fluffy.Expect.t()
  defdelegate enabled(locator, options \\ []), to: Fluffy.Expect, as: :to_be_enabled

  @doc group: "Locator assertions"
  @doc playwright_only: true
  @doc "Equivalent to `Fluffy.Expect.to_be_focused/2`. Requires Playwright."
  @spec focused(Fluffy.Locator.t(), [Fluffy.Expect.to_be_focused_option()]) :: Fluffy.Expect.t()
  defdelegate focused(locator, options \\ []), to: Fluffy.Expect, as: :to_be_focused

  @doc group: "Locator assertions"
  @doc playwright_only: true
  @doc "Equivalent to `Fluffy.Expect.to_be_in_viewport/2`. Requires Playwright."
  @spec in_viewport(Fluffy.Locator.t(), [Fluffy.Expect.to_be_in_viewport_option()]) :: Fluffy.Expect.t()
  defdelegate in_viewport(locator, options \\ []), to: Fluffy.Expect, as: :to_be_in_viewport

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_be_checked/2`."
  @spec checked(Fluffy.Locator.t(), [Fluffy.Expect.to_be_checked_option()]) :: Fluffy.Expect.t()
  defdelegate checked(locator, options \\ []), to: Fluffy.Expect, as: :to_be_checked

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_have_value/3`."
  @spec value(Fluffy.Locator.t(), String.t(), [Fluffy.Expect.to_have_value_option()]) :: Fluffy.Expect.t()
  defdelegate value(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_have_value

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_have_values/3`."
  @spec values(Fluffy.Locator.t(), [term()], [Fluffy.Expect.to_have_values_option()]) :: Fluffy.Expect.t()
  defdelegate values(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_have_values

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_have_text/3`."
  @spec text(Fluffy.Locator.t(), Fluffy.Expect.text_expectation() | [Fluffy.Expect.text_expectation()], [
          Fluffy.Expect.to_have_text_option()
        ]) :: Fluffy.Expect.t()
  defdelegate text(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_have_text

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_contain_text/3`."
  @spec contain_text(Fluffy.Locator.t(), Fluffy.Expect.text_expectation() | [Fluffy.Expect.text_expectation()], [
          Fluffy.Expect.to_contain_text_option()
        ]) :: Fluffy.Expect.t()
  defdelegate contain_text(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_contain_text

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_have_attribute/4`."
  @spec attribute(Fluffy.Locator.t(), String.t()) :: Fluffy.Expect.t()
  @spec attribute(
          Fluffy.Locator.t(),
          String.t(),
          Fluffy.Expect.text_expectation() | nil | [Fluffy.Expect.to_have_attribute_option()]
        ) :: Fluffy.Expect.t()
  @spec attribute(Fluffy.Locator.t(), String.t(), Fluffy.Expect.text_expectation() | nil, [
          Fluffy.Expect.to_have_attribute_option()
        ]) :: Fluffy.Expect.t()
  defdelegate attribute(locator, name, value \\ nil, options \\ []), to: Fluffy.Expect, as: :to_have_attribute

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_have_class/3`."
  @spec class(Fluffy.Locator.t(), Fluffy.Expect.text_expectation() | [Fluffy.Expect.text_expectation()], [
          Fluffy.Expect.to_have_class_option()
        ]) :: Fluffy.Expect.t()
  defdelegate class(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_have_class

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_contain_class/3`."
  @spec contain_class(Fluffy.Locator.t(), String.t() | [String.t()], [Fluffy.Expect.to_contain_class_option()]) ::
          Fluffy.Expect.t()
  defdelegate contain_class(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_contain_class

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_have_id/3`."
  @spec id(Fluffy.Locator.t(), Fluffy.Expect.text_expectation(), [Fluffy.Expect.to_have_id_option()]) :: Fluffy.Expect.t()
  defdelegate id(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_have_id

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_be_attached/2`."
  @spec attached(Fluffy.Locator.t(), [Fluffy.Expect.to_be_attached_option()]) :: Fluffy.Expect.t()
  defdelegate attached(locator, options \\ []), to: Fluffy.Expect, as: :to_be_attached

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_be_hidden/2`."
  @spec hidden(Fluffy.Locator.t(), [Fluffy.Expect.to_be_hidden_option()]) :: Fluffy.Expect.t()
  defdelegate hidden(locator, options \\ []), to: Fluffy.Expect, as: :to_be_hidden

  @doc group: "Locator assertions"
  @doc "Equivalent to `Fluffy.Expect.to_be_empty/2`."
  @spec empty(Fluffy.Locator.t(), [Fluffy.Expect.to_be_empty_option()]) :: Fluffy.Expect.t()
  defdelegate empty(locator, options \\ []), to: Fluffy.Expect, as: :to_be_empty

  @doc group: "Page assertions"
  @doc "Equivalent to `Fluffy.Expect.page_to_have_title/2`."
  @spec page_title(Fluffy.Page.title_expectation(), [Fluffy.Expect.page_to_have_title_option()]) :: Fluffy.Expect.t()
  defdelegate page_title(expected, options \\ []), to: Fluffy.Expect, as: :page_to_have_title

  @doc group: "Page assertions"
  @doc "Equivalent to `Fluffy.Expect.page_to_have_url/2`."
  @spec page_url(Fluffy.Page.url_expectation(), [Fluffy.Expect.page_to_have_url_option()]) :: Fluffy.Expect.t()
  defdelegate page_url(expected, options \\ []), to: Fluffy.Expect, as: :page_to_have_url

  @doc group: "Page assertions"
  @doc "Equivalent to `Fluffy.Expect.page_to_have_opener/2`."
  @spec page_opener(Fluffy.Page.t() | nil, [Fluffy.Expect.option()]) :: Fluffy.Expect.t()
  defdelegate page_opener(expected, options \\ []), to: Fluffy.Expect, as: :page_to_have_opener

  @doc group: "Events"
  @doc "Equivalent to `Fluffy.Expect.expect_event/3`."
  @spec assert_event(Fluffy.Session.t(), Fluffy.Event.t(), (Fluffy.Session.t() -> term())) :: Fluffy.Session.t()
  defdelegate assert_event(session, event, action), to: Fluffy.Expect, as: :expect_event

  @doc group: "Events"
  @doc "Equivalent to `Fluffy.Expect.expect_event/4`."
  @spec assert_event(
          Fluffy.Session.t(),
          Fluffy.Event.t(),
          (Fluffy.Session.t() -> term()),
          (term() -> term()) | [Fluffy.Event.option()]
        ) :: Fluffy.Session.t()
  defdelegate assert_event(session, event, action, assertion_or_options), to: Fluffy.Expect, as: :expect_event

  @doc group: "Events"
  @doc "Equivalent to `Fluffy.Expect.expect_event/5`."
  @spec assert_event(Fluffy.Session.t(), Fluffy.Event.t(), (Fluffy.Session.t() -> term()), (term() -> term()), [
          Fluffy.Event.option()
        ]) :: Fluffy.Session.t()
  defdelegate assert_event(session, event, action, assertion, options), to: Fluffy.Expect, as: :expect_event
end
