defmodule Fluffy.Case do
  @moduledoc """
  Registers the test for Fluffy, for every kind of test: Phoenix-only, browser or both, with
  the native API or the `Fluffy.PhoenixTest` facade.

  It adds `use PlaywrightEx.Test`, so Playwright sessions work: a test takes a browser from
  `PlaywrightEx.Test.BrowserPool.browser/1` only when it starts one (see
  [Playwright setup](installation.md#playwright-setup)). It also records the test's timeout, so
  a Phoenix operation that would outlast it, such as a LiveView action that never finds its
  element, fails with Fluffy's error and "Test timeout of 60000ms exceeded." just before ExUnit
  kills the test, as a Playwright one does.

  The imports and the session are yours. With the native API:

      defmodule MyAppWeb.ThreeHeadedDogTest do
        use MyAppWeb.ConnCase, async: true
        use Fluffy.Case
        use Fluffy.Assert

        import Fluffy
        import Fluffy.Locator

        setup context do
          %{session: start_session(context[:backend] || :phoenix)}
        end

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

  The `backend` tag is this setup's own: name it as you like, or start sessions in the tests.
  With the facade, `import Fluffy.PhoenixTest` takes the place of the three native lines.

  Order matters. `use Fluffy.Case` comes after your own case template (`ConnCase` or
  `DataCase`), or after `use ExUnit.Case, async: true` without one, so the template's setup,
  such as the Ecto sandbox owner, runs first and stops after the sessions close. Used before
  it, the template's `use ExUnit.Case` imports `test` again, and the first test fails to
  compile on a `test/3` imported from both `ExUnit.Case` and `PlaywrightEx.Test`.

  ## Your own case template

  Put `use Fluffy.Case` in your template's `using`, with your imports and session setup
  after it there; the template's own `setup`, here the sandbox owner's, runs before them:

      defmodule MyAppWeb.FeatureCase do
        use ExUnit.CaseTemplate

        using do
          quote do
            use Fluffy.Case
            use Fluffy.Assert

            import Fluffy
            import Fluffy.Locator

            setup context do
              %{session: start_session(context[:backend] || :phoenix)}
            end
          end
        end

        setup tags do
          MyApp.DataCase.setup_sandbox(tags)
          :ok
        end
      end

  When the template's own `setup` starts the session, also make `use Fluffy.Case` the first
  line of its body. A template's own `setup` callbacks run before those its `using` brings in,
  so the test is then registered before them (a Playwright session started before the
  registration makes it raise). The line in `using` stays, as it brings the `test` macro to
  each module; there it registers nothing again:

      defmodule MyAppWeb.FeatureCase do
        use ExUnit.CaseTemplate
        use Fluffy.Case

        using do
          quote do
            use Fluffy.Case
            use Fluffy.Assert

            import Fluffy
            import Fluffy.Locator
          end
        end

        setup tags do
          MyApp.DataCase.setup_sandbox(tags)
          %{session: Fluffy.start_session(tags[:backend] || :phoenix)}
        end
      end
  """

  defmacro __using__(opts) do
    if opts != [] do
      raise ArgumentError, "use Fluffy.Case takes no options, got: #{Macro.to_string(opts)}"
    end

    macros = __CALLER__.macros

    if not ({:test, 3} in Keyword.get(macros, ExUnit.Case, []) or
              {:test, 3} in Keyword.get(macros, PlaywrightEx.Test, []) or
              {:using, 1} in Keyword.get(macros, ExUnit.CaseTemplate, [])) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "use Fluffy.Case must come after use ExUnit.Case (or in a case template's body or using)"
    end

    quote do
      use PlaywrightEx.Test

      setup {Fluffy.Case, :put_test_timeout}
    end
  end

  # Records the test's ExUnit timeout, so a Phoenix operation that would outlast it fails
  # with Fluffy's error just before ExUnit kills the test, as PlaywrightEx.Test makes a
  # Playwright one fail then. Sessions started from a `Task` of the test get it too. Once per
  # test, at its registration: a template's body and its `using` may both bring it.
  @doc false
  @spec put_test_timeout(map()) :: :ok
  def put_test_timeout(context) do
    case Registry.lookup(Fluffy.TestTimeout, self()) do
      [] -> Fluffy.TestTimeout.put(context)
      _recorded -> :ok
    end
  end
end
