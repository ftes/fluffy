defmodule Fluffy.Assert.Steps do
  # `use Fluffy.Assert`'s `assert/2` and `refute/2`: macros, so an assertion with a message expands
  # at the caller, as with `use Playwright.Test` alone. Its step has the caller's expression and
  # line, and ExUnit's own `refute(value, expr: ...)` (of `refute match?(...)`) passes through to
  # ExUnit. `Fluffy.Assert.assert/2` and `refute/2` stay functions for qualified calls.
  @moduledoc false

  alias Playwright.Test.Assertions

  require Assertions

  @assertions Assertions

  defmacro assert(subject, expectation_or_message),
    do: assertion(:assert, subject, Macro.expand(expectation_or_message, __CALLER__))

  defmacro refute(subject, expectation_or_message),
    do: assertion(:refute, subject, Macro.expand(expectation_or_message, __CALLER__))

  # A message is a string (also a module attribute's, expanded, or one with interpolation) or a
  # list, never a `Fluffy.Expect`; anything else, such as a message in a variable, is told apart
  # when it runs, without the caller's line.
  defp assertion(kind, subject, message)
       when is_binary(message) or is_list(message) or (is_tuple(message) and elem(message, 0) == :<<>>) do
    quote do
      require unquote(@assertions)

      unquote(@assertions).unquote(kind)(unquote(subject), unquote(message))
    end
  end

  defp assertion(kind, subject, expectation_or_message) do
    quote do
      Fluffy.Assert.Steps.__assertion__(unquote(kind), unquote(subject), unquote(expectation_or_message))
    end
  end

  # Playwright's records a step when the running test has `assert_steps` on, else is ExUnit's.
  @doc false
  def __assertion__(:assert, session, %Fluffy.Expect{} = expectation), do: Fluffy.Assert.assert(session, expectation)
  def __assertion__(:refute, session, %Fluffy.Expect{} = expectation), do: Fluffy.Assert.refute(session, expectation)
  def __assertion__(:assert, value, message), do: Assertions.assert(value, message)
  def __assertion__(:refute, value, message), do: Assertions.refute(value, message)
end
