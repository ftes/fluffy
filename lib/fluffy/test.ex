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
  every module with Fluffy sessions; `Fluffy.Case` does it for you. It registers
  `setup/1`, and a second `use` in the same module does nothing. It also uses
  `PlaywrightEx.Test`, which records the traces, screenshots and videos of Playwright
  sessions (`config :playwright_ex, :test`) and marks each test's result for them. Of
  `PlaywrightEx.Test`, it imports only the `test` macros, as its fragment names clash with
  `Fluffy.Playwright`'s.

  To run `setup/1` yourself, such as after your own setup, `use PlaywrightEx.Test` instead
  and call it. To override the artifact modes for a test, call
  `PlaywrightEx.Test.record_artifacts/2` in its setup, before its first session.
  """

  defmacro __using__(options) do
    if options != [] do
      raise ArgumentError, "use Fluffy.Test takes no options, got: #{Macro.to_string(options)}"
    end

    module = __CALLER__.module

    # Set as the macro expands, not by the code it returns: a later `use` in the same
    # module body expands before that code runs.
    if module && Module.has_attribute?(module, :fluffy_test) do
      :ok
    else
      if module, do: Module.put_attribute(module, :fluffy_test, true)

      quote do
        use PlaywrightEx.Test

        import PlaywrightEx.Test, only: [test: 1, test: 2, test: 3]

        setup context do
          Fluffy.Test.setup(context)
        end
      end
    end
  end

  @doc """
  Establishes Fluffy lifecycle management for the current ExUnit test, as
  `use Fluffy.Test` does.

  With `config :fluffy, ecto_repos:`, browser sessions carry the test process's Ecto
  SQL sandbox metadata. The sandbox owner is the application's, started by its
  DataCase or ConnCase; see [Ecto sandbox](installation.md#ecto-sandbox).
  """
  @spec setup(map()) :: :ok
  def setup(context) when is_map(context), do: Fluffy.TestScope.setup(context)
end
