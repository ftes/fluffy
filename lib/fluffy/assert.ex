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

  @doc "Imports the assertion vocabulary without conflicts with ExUnit."
  defmacro __using__(_options) do
    quote do
      import ExUnit.Assertions, except: [assert: 2, refute: 2]
      import Fluffy.Assert
    end
  end

  @doc "Executes a typed expectation, or delegates an ordinary assertion with a message to ExUnit."
  def assert(session, %Fluffy.Expect{} = expectation), do: Fluffy.Expect.expect(session, expectation)
  def assert(expression, message), do: ExUnit.Assertions.assert(expression, message)

  @doc "Executes a negated expectation, or delegates an ordinary refutation with a message to ExUnit."
  def refute(session, %Fluffy.Expect{} = expectation), do: Fluffy.Expect.expect(session, Fluffy.Expect.not_(expectation))

  def refute(expression, message), do: ExUnit.Assertions.refute(expression, message)

  @doc "Executes a typed expectation with additional options."
  def assert(session, %Fluffy.Expect{} = expectation, options), do: Fluffy.Expect.expect(session, expectation, options)

  @doc "Executes a negated expectation with additional options."
  def refute(session, %Fluffy.Expect{} = expectation, options),
    do: Fluffy.Expect.expect(session, Fluffy.Expect.not_(expectation), options)

  @doc """
  Asserts that the locator resolves to a visible element and returns the session.

  Equivalent to `assert(session, visible(locator), options)`.
  For DOM presence regardless of visibility, use a `count` expectation.
  """
  def assert_has(session, %Fluffy.Locator{} = locator, options \\ []), do: assert(session, visible(locator), options)

  @doc """
  Asserts that the locator is absent or hidden and returns the session.

  Equivalent to `refute(session, visible(locator), options)`.
  Use `count(locator, 0)` to require DOM absence.
  """
  def refute_has(session, %Fluffy.Locator{} = locator, options \\ []), do: refute(session, visible(locator), options)

  @doc "Equivalent to `Fluffy.Expect.to_have_count/3`."
  defdelegate count(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_have_count

  @doc "Equivalent to `Fluffy.Expect.to_be_visible/2`."
  defdelegate visible(locator, options \\ []), to: Fluffy.Expect, as: :to_be_visible

  @doc "Equivalent to `Fluffy.Expect.to_be_disabled/2`."
  defdelegate disabled(locator, options \\ []), to: Fluffy.Expect, as: :to_be_disabled

  @doc "Equivalent to `Fluffy.Expect.to_be_editable/2`."
  defdelegate editable(locator, options \\ []), to: Fluffy.Expect, as: :to_be_editable

  @doc "Equivalent to `Fluffy.Expect.to_be_enabled/2`."
  defdelegate enabled(locator, options \\ []), to: Fluffy.Expect, as: :to_be_enabled

  @doc "Equivalent to `Fluffy.Expect.to_be_focused/2`."
  defdelegate focused(locator, options \\ []), to: Fluffy.Expect, as: :to_be_focused

  @doc "Equivalent to `Fluffy.Expect.to_be_checked/2`."
  defdelegate checked(locator, options \\ []), to: Fluffy.Expect, as: :to_be_checked

  @doc "Equivalent to `Fluffy.Expect.to_have_value/3`."
  defdelegate value(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_have_value

  @doc "Equivalent to `Fluffy.Expect.to_have_values/3`."
  defdelegate values(locator, expected, options \\ []), to: Fluffy.Expect, as: :to_have_values

  @doc "Equivalent to `Fluffy.Expect.page_to_have_title/2`."
  defdelegate page_title(expected, options \\ []), to: Fluffy.Expect, as: :page_to_have_title

  @doc "Equivalent to `Fluffy.Expect.page_to_have_url/2`."
  defdelegate page_url(expected, options \\ []), to: Fluffy.Expect, as: :page_to_have_url

  @doc "Equivalent to `Fluffy.Expect.page_to_have_status/2`."
  defdelegate page_status(expected, options \\ []), to: Fluffy.Expect, as: :page_to_have_status

  @doc "Equivalent to `Fluffy.Expect.page_to_have_opener/2`."
  defdelegate page_opener(expected, options \\ []), to: Fluffy.Expect, as: :page_to_have_opener

  @doc "Equivalent to `Fluffy.Expect.expect_event/3`."
  defdelegate assert_event(session, event, action), to: Fluffy.Expect, as: :expect_event

  @doc "Equivalent to `Fluffy.Expect.expect_event/4`."
  defdelegate assert_event(session, event, action, assertion_or_options), to: Fluffy.Expect, as: :expect_event

  @doc "Equivalent to `Fluffy.Expect.expect_event/5`."
  defdelegate assert_event(session, event, action, assertion, options), to: Fluffy.Expect, as: :expect_event
end
