defmodule Fluffy.TestScopeSetupTest do
  use ExUnit.Case, async: false
  use PlaywrightEx.Test

  alias Fluffy.TestScope
  alias Fluffy.TestWeb.Endpoint

  setup do
    previous_repos = Application.get_env(:fluffy, :ecto_repos, :not_configured)

    on_exit(fn ->
      case previous_repos do
        :not_configured -> Application.delete_env(:fluffy, :ecto_repos)
        repos -> Application.put_env(:fluffy, :ecto_repos, repos)
      end
    end)

    :ok
  end

  test "setup creates a lifecycle scope without Ecto repositories", context do
    Application.delete_env(:fluffy, :ecto_repos)

    assert :ok = Fluffy.Test.setup(context)

    assert %{
             owners: [],
             sandbox_header: nil,
             test_context: %{module: __MODULE__, test: test}
           } = TestScope.current()

    assert test == context.test
  end

  test "setup can explicitly omit configured sandbox resources", context do
    Application.put_env(:fluffy, :ecto_repos, [Fluffy.TestRepo])

    assert :ok = Fluffy.Test.setup(context, sandbox: false)
    assert %{owners: [], sandbox_header: nil} = TestScope.current()
  end

  test "setup rejects a second lifecycle scope for the same test", context do
    Application.delete_env(:fluffy, :ecto_repos)

    assert :ok = Fluffy.Test.setup(context)

    assert_raise ArgumentError, ~r/Fluffy\.Test\.setup.*already been called/, fn ->
      Fluffy.Test.setup(context)
    end
  end

  test "session creation requires setup" do
    Application.delete_env(:fluffy, :ecto_repos)
    Process.delete({TestScope, :current})

    message = ~r/Fluffy\.Test\.setup\(context\).*before.*start_session/

    assert_raise ArgumentError, message, fn ->
      Fluffy.start_session(:phoenix,
        endpoint: Endpoint,
        base_url: Fluffy.TestServer.base_url()
      )
    end

    assert_raise ArgumentError, message, fn ->
      Fluffy.start_session(:playwright, base_url: Fluffy.TestServer.base_url())
    end
  end

  test "raw scope attachment is not a session option", context do
    Application.delete_env(:fluffy, :ecto_repos)
    assert :ok = Fluffy.Test.setup(context)

    assert_raise ArgumentError, ~r/unknown.*scope|unknown keys.*scope/, fn ->
      Fluffy.start_session(:phoenix,
        endpoint: Endpoint,
        base_url: Fluffy.TestServer.base_url(),
        scope: self()
      )
    end
  end

  test "setup validates its typed options", context do
    Application.delete_env(:fluffy, :ecto_repos)

    assert_raise NimbleOptions.ValidationError, ~r/unknown options.*:mystery/, fn ->
      Fluffy.Test.setup(context, mystery: true)
    end

    assert_raise NimbleOptions.ValidationError,
                 ~r/:repos.*invalid value|invalid value.*:repos/,
                 fn ->
                   Fluffy.Test.setup(context, repos: :not_a_list)
                 end
  end
end

defmodule Fluffy.TestScopeWithoutPlaywrightTest do
  # A module without `use Fluffy.Test`: Phoenix sessions work, Playwright sessions need it.
  use ExUnit.Case, async: true

  setup context do
    Fluffy.Test.setup(context, sandbox: false)
  end

  test "runs Phoenix sessions and rejects Playwright ones" do
    Fluffy.start_session(:phoenix, endpoint: Fluffy.TestWeb.Endpoint)

    assert_raise ArgumentError, ~r/use PlaywrightEx.Test/, fn ->
      Fluffy.start_session(:playwright, base_url: Fluffy.TestServer.base_url())
    end
  end
end
