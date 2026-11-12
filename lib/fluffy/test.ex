defmodule Fluffy.Test do
  @moduledoc """
  ExUnit lifecycle setup for Fluffy tests.

      defmodule MyAppWeb.CreatureTest do
        use ExUnit.Case, async: true
        use Fluffy.Test

        test "puts Fluffy to sleep" do
          ...
        end
      end

  `use Fluffy.Test` comes after `use ExUnit.Case` (or in a case template's `using`), in
  every module with Fluffy sessions. It registers `setup/2` with its options, such as
  `use Fluffy.Test, sandbox: false`. It also uses `PlaywrightEx.Test`, which records the
  traces, screenshots and videos of Playwright sessions (`config :playwright_ex, :test`)
  and marks each test's result for them. Of `PlaywrightEx.Test`, it imports only the
  `test` macros, as its fragment names clash with `Fluffy.Playwright`'s.

  To run `setup/2` yourself, such as after your own setup, `use PlaywrightEx.Test` instead
  and call it. To override the artifact modes for a test, call
  `PlaywrightEx.Test.record_artifacts/2` in its setup, before its first session.
  """

  defmacro __using__(options) do
    quote do
      use PlaywrightEx.Test

      import PlaywrightEx.Test, only: [test: 1, test: 2, test: 3]

      setup context do
        Fluffy.Test.setup(context, unquote(options))
      end
    end
  end

  @doc """
  Establishes Fluffy lifecycle management for the current ExUnit test, as
  `use Fluffy.Test` does.

  When Ecto repositories are configured, Fluffy also starts or adopts their SQL
  sandbox ownership. Pass `sandbox: false` to establish lifecycle management
  without database ownership.

  ## Options

  #{NimbleOptions.docs(Fluffy.Options.setup_schema())}
  """
  @type setup_option ::
          unquote(NimbleOptions.option_typespec(Fluffy.Options.setup_schema()))
  @spec setup(map(), [setup_option()]) :: :ok
  def setup(context, options \\ []) when is_map(context) and is_list(options) do
    options = Fluffy.Options.validate_setup!(options)
    repos = Keyword.get(options, :repos, Application.get_env(:fluffy, :ecto_repos, []))
    sandbox? = Keyword.get(options, :sandbox, repos != [])

    if sandbox? and repos == [] do
      raise ArgumentError,
            "Fluffy test setup requested sandbox ownership but no Ecto repositories are configured"
    end

    Fluffy.TestScope.setup(context,
      sandbox: if(sandbox?, do: {Fluffy.Sandbox, :acquire, [context, repos]}, else: false)
    )
  end
end
