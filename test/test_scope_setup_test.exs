defmodule Fluffy.TestScopeSetupTest do
  use ExUnit.Case, async: false
  use PlaywrightEx.Test

  alias Fluffy.Support.Repo
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint
  alias Fluffy.TestScope

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
             sandbox_header: nil,
             test_context: %{module: __MODULE__, test: test}
           } = TestScope.current()

    assert test == context.test
  end

  test "setup builds the sandbox header of the configured repos for the test process", context do
    Application.put_env(:fluffy, :ecto_repos, [Repo])

    assert :ok = Fluffy.Test.setup(context)
    assert %{sandbox_header: {"user-agent", metadata}} = TestScope.current()

    assert Phoenix.Ecto.SQL.Sandbox.decode_metadata(metadata) == %{
             repo: [Repo],
             owner: self(),
             trap_exit: true
           }
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
        base_url: Server.base_url()
      )
    end

    assert_raise ArgumentError, message, fn ->
      Fluffy.start_session(:playwright, base_url: Server.base_url())
    end
  end

  test "raw scope attachment is not a session option", context do
    Application.delete_env(:fluffy, :ecto_repos)
    assert :ok = Fluffy.Test.setup(context)

    assert_raise ArgumentError, ~r/unknown.*scope|unknown keys.*scope/, fn ->
      Fluffy.start_session(:phoenix,
        endpoint: Endpoint,
        base_url: Server.base_url(),
        scope: self()
      )
    end
  end

  test "use Fluffy.Test takes no options" do
    # A module without `use Fluffy.Test`: Phoenix sessions work, Playwright sessions need it.
    assert_raise ArgumentError, ~r/use Fluffy.Test takes no options, got: \[sandbox: false\]/, fn ->
      Code.compile_quoted(
        quote do
          defmodule Fluffy.TestScopeSetupTest.WithOptions do
            @moduledoc false
            use ExUnit.Case, register: false
            use Fluffy.Test, sandbox: false
          end
        end
      )
    end
  end
end

defmodule Fluffy.TestScopeWithoutPlaywrightTest do
  use ExUnit.Case, async: true

  setup context do
    Fluffy.Test.setup(context)
  end

  test "runs Phoenix sessions and rejects Playwright ones" do
    Fluffy.start_session(:phoenix, endpoint: Fluffy.Support.Web.Endpoint)

    assert_raise ArgumentError, ~r/use PlaywrightEx.Test/, fn ->
      Fluffy.start_session(:playwright, base_url: Fluffy.Support.Server.base_url())
    end
  end
end
