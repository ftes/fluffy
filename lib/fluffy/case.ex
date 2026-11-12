defmodule Fluffy.Case do
  @moduledoc """
  A case template for Fluffy tests, a recipe as much as an API.

      defmodule MyAppWeb.ThreeHeadedDogTest do
        use MyAppWeb.ConnCase, async: true
        use Fluffy.Case

        test "Fluffy guards the trapdoor", %{session: session} do
          session
          |> visit("/third-floor-corridor")
          |> assert(visible(by_text("Trapdoor")))
        end

        @tag backend: :playwright
        test "Fluffy falls asleep to the harp", %{session: session} do
          session
          |> visit("/third-floor-corridor")
          |> click(by_role(:button, name: "Play the harp"))
          |> assert(visible(by_text("Fluffy is asleep")))
        end
      end

  It adds `use PlaywrightEx.Test` and `use Fluffy.Assert`, imports `Fluffy` and
  `Fluffy.Locator`, aliases `Fluffy.Event`, records the test's timeout and starts a session
  per test, in its `session`: Phoenix by default, the backend of a `@tag`, `@describetag` or
  `@moduletag` `backend:` otherwise.

  Order matters. `use Fluffy.Case` comes after your own case template (`ConnCase` or
  `DataCase`), so its setup, such as the Ecto sandbox owner, runs first and stops after
  the sessions close. Used before it, the template's `use ExUnit.Case` imports `test`
  again, and the first test fails to compile on a `test/3` imported from both
  `ExUnit.Case` and `PlaywrightEx.Test`. Without your own template, `use Fluffy.Case,
  async: true` stands alone.

  It is only a few lines: to change them, copy them into your own case template's
  `using`, keeping the session setup after `use PlaywrightEx.Test`. On Firefox, write your
  own session setup with `browser: PlaywrightEx.Test.BrowserPool.exclusive()`; see
  [Playwright setup](installation.md#playwright-setup).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use PlaywrightEx.Test
      use Fluffy.Assert

      import Fluffy
      import Fluffy.Locator

      alias Fluffy.Event

      setup {Fluffy.Case, :put_test_timeout}
      setup {Fluffy.Case, :start_session}
    end
  end

  @doc """
  Records the test's ExUnit timeout, so a Phoenix operation that would outlast it, such as a
  LiveView action that never finds its element, fails with Fluffy's error and "Test timeout of
  60000ms exceeded." just before ExUnit kills the test, as PlaywrightEx.Test makes a
  Playwright one fail then. Sessions started from a `Task` of the test get it too.
  """
  @spec put_test_timeout(map()) :: :ok
  def put_test_timeout(context), do: Fluffy.TestTimeout.put(context)

  @doc "Starts the test's session, with the context's `backend` (`:phoenix` by default)."
  @spec start_session(map()) :: %{session: Fluffy.Session.t()}
  def start_session(context), do: %{session: Fluffy.start_session(Map.get(context, :backend, :phoenix))}
end
