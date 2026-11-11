defmodule Fluffy.Test do
  @moduledoc """
  ExUnit lifecycle setup for Fluffy tests.

  A module that starts Playwright sessions adds `use Fluffy.Test` after `use ExUnit.Case`
  (or in a case template's `using`). It uses `PlaywrightEx.Test`, which marks the test's
  result for its artifacts and pool, and imports only its `test` macros, whose fragment
  names would clash with `Fluffy.Playwright`'s.
  """

  defmacro __using__(_options) do
    quote do
      use PlaywrightEx.Test

      import PlaywrightEx.Test, only: [test: 1, test: 2, test: 3]

      @moduletag fluffy_playwright: true
    end
  end

  @doc """
  Establishes Fluffy lifecycle management for the current ExUnit test.

  Call this from the test case's setup callback before starting sessions. When
  Ecto repositories are configured, Fluffy also starts or adopts their SQL
  sandbox ownership. Pass `sandbox: false` to establish lifecycle management
  without database ownership.

  In a module with `use Fluffy.Test`, which Playwright sessions need, it also
  calls `PlaywrightEx.Test.record_artifacts/2`: that records the traces, screenshots and
  videos of the test's Playwright sessions. Its modes come from
  `config :playwright_ex, :test`, overridden by `trace:`, `screenshot:` and `video:`.

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

    :ok =
      Fluffy.TestScope.setup(context,
        sandbox: if(sandbox?, do: {Fluffy.Sandbox, :acquire, [context, repos]}, else: false)
      )

    if context[:fluffy_playwright] do
      PlaywrightEx.Test.record_artifacts(context, Keyword.take(options, [:trace, :screenshot, :video]))
    else
      :ok
    end
  end
end
