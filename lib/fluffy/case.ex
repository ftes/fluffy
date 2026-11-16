defmodule Fluffy.Case do
  @moduledoc """
  Registers the test for Fluffy, for every kind of test: Phoenix-only, browser or both, with
  the native API or the `Fluffy.PhoenixTest` facade.

  It adds `use Playwright.Test`, so Playwright sessions work: a test takes a browser from
  `Playwright.Test.BrowserPool.browser/1` only when it starts one (see
  [Playwright setup](installation.md#playwright-setup)). It also bounds Phoenix operations by
  the test's timeout, so one that would outlast it, such as a LiveView action that never finds
  its element, fails with Fluffy's error and "Test timeout of 60000ms exceeded." just before
  ExUnit kills the test, as a Playwright one does.

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
  compile on a `test/3` imported from both `ExUnit.Case` and `Playwright.Test`.

  ## Options

  The options are `use Playwright.Test`'s: `trace:`, `screenshot:` and `video:` for the
  module, over the config and under its tags, and `tags: false`, so tags don't set them (see
  `Playwright.Test`). An unknown option fails to compile. ExUnit.Case's options such as
  `async:` belong on `use ExUnit.Case`; `use Fluffy.Case` ignores them.

      use Fluffy.Case, trace: :on

  ## Your own case template

  Put `use Fluffy.Case` in your template's `using`, with your imports and session setup
  after it there; the template's own `setup`, here the sandbox owner's, runs before them. It
  forwards the module's options, so `use MyAppWeb.FeatureCase, async: true, trace: :on` works:

      defmodule MyAppWeb.FeatureCase do
        use ExUnit.CaseTemplate

        using opts do
          quote do
            use Fluffy.Case, unquote(opts)
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

  When the template's own `setup` starts the session, also put `use Fluffy.Case` right after
  `use ExUnit.CaseTemplate`. A template's own `setup` callbacks run before those its `using`
  brings in, so the test is then registered before them (a Playwright session started before
  the registration makes it raise). The line in `using` stays, as it brings the `test` macro
  to each module and takes the options; there it registers nothing again. The one in the body
  takes none:

      defmodule MyAppWeb.FeatureCase do
        use ExUnit.CaseTemplate
        use Fluffy.Case

        using opts do
          quote do
            use Fluffy.Case, unquote(opts)
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
    macros = __CALLER__.macros

    if not ({:test, 3} in Keyword.get(macros, ExUnit.Case, []) or
              {:test, 3} in Keyword.get(macros, Playwright.Test, []) or
              {:using, 1} in Keyword.get(macros, ExUnit.CaseTemplate, [])) do
      raise CompileError,
        file: __CALLER__.file,
        line: __CALLER__.line,
        description: "use Fluffy.Case must come after use ExUnit.Case (or in a case template's body or using)"
    end

    quote do
      use Playwright.Test, unquote(opts)
    end
  end
end
