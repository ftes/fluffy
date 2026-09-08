defmodule Fluffy.Test do
  @moduledoc """
  ExUnit lifecycle setup for Fluffy tests.
  """

  @doc """
  Establishes Fluffy lifecycle management for the current ExUnit test.

  Call this from the test case's setup callback before starting sessions. When
  Ecto repositories are configured, Fluffy also starts or adopts their SQL
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
      sandbox: if(sandbox?, do: {Fluffy.Sandbox, :acquire, [context, repos]}, else: false),
      timeout: Keyword.get(options, :timeout, 5_000)
    )
  end
end
