defmodule Fluffy.CaseTest do
  # Fluffy.Case only registers the test: the imports and the session are the module's own.
  use ExUnit.Case, async: true
  use Fluffy.Case

  test "imports nothing of Fluffy and starts no session", context do
    refute Map.has_key?(context, :session)
    refute Keyword.has_key?(__ENV__.functions, Fluffy)
    refute Keyword.has_key?(__ENV__.functions, Fluffy.Locator)
    assert PlaywrightEx.Test.info().test_pid == self()
  end

  @tag timeout: 30_000
  test "bounds Phoenix waits by the test's timeout" do
    assert {30_000, _backstop} = Fluffy.TestTimeout.fetch()
  end

  test "comes after use ExUnit.Case and takes no options" do
    assert_raise CompileError, ~r/use Fluffy.Case must come after use ExUnit.Case/, fn ->
      Code.compile_string("defmodule Fluffy.CaseTest.Misplaced, do: use(Fluffy.Case)")
    end

    assert_raise ArgumentError, ~r/use Fluffy.Case takes no options/, fn ->
      Code.compile_string("""
      defmodule Fluffy.CaseTest.Standalone do
        use ExUnit.Case
        use Fluffy.Case, async: true
      end
      """)
    end
  end
end

defmodule Fluffy.CaseNativeTest do
  use ExUnit.Case, async: true
  use Fluffy.Case
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  setup context do
    %{session: start_session(context[:backend] || :phoenix)}
  end

  test "runs a Phoenix session of its own setup", %{session: session} do
    session
    |> visit("/live/fluffy")
    |> assert(visible(by_text("Guardian head count: 0")))

    assert Fluffy.Session.current_driver(session) == :live
  end

  @tag backend: :playwright
  test "runs a Playwright session of its own setup", %{session: session} do
    session
    |> visit("/live/fluffy")
    |> assert(visible(by_text("Guardian head count: 0")))

    assert Fluffy.Session.current_driver(session) == :playwright
  end
end

defmodule Fluffy.CasePhoenixTestFacadeTest do
  # The facade's names don't clash with what Fluffy.Case imports.
  use ExUnit.Case, async: true
  use Fluffy.Case

  import Fluffy.PhoenixTest

  setup context do
    %{session: start_session(context[:backend] || :phoenix)}
  end

  test "runs a Phoenix facade session", %{session: session} do
    session
    |> visit("/live/fluffy")
    |> assert_has("body", text: "Guardian head count: 0")
  end

  @tag backend: :playwright
  test "runs a Playwright facade session", %{session: session} do
    session
    |> visit("/live/fluffy")
    |> assert_has("body", text: "Guardian head count: 0")
  end
end

defmodule Fluffy.CaseTest.FeatureCase do
  # The recommended template: registered in its body, before its own setups, and again in
  # `using`, which only brings the `test` macro then.
  @moduledoc false
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

  setup context do
    %{
      session: Fluffy.start_session(context[:backend] || :phoenix),
      test_timeout: Fluffy.TestTimeout.fetch()
    }
  end
end

defmodule Fluffy.CaseTemplateTest do
  use Fluffy.CaseTest.FeatureCase, async: true

  @tag backend: :playwright
  test "starts a Playwright session in the template's setup", %{session: session} do
    session
    |> visit("/live/fluffy")
    |> assert(visible(by_text("Guardian head count: 0")))

    assert Fluffy.Session.current_driver(session) == :playwright
  end

  test "the template's setups see the test's backstop", %{test_timeout: test_timeout} do
    assert {_timeout, _backstop} = test_timeout
    assert Fluffy.TestTimeout.fetch() == test_timeout
  end
end

defmodule Fluffy.CaseBrowserLeaseTest do
  # A test takes a browser from PlaywrightEx.Test's pool, and with it one of `workers`
  # seats, only for a Playwright session. The pool has no public view of its seats, so this
  # reads its state: the scopes that hold seats, here the test process, until the test's `on_exit`.
  use ExUnit.Case, async: true
  use Fluffy.Case
  use Fluffy.Assert

  import Fluffy
  import Fluffy.Locator

  setup context do
    %{session: start_session(context[:backend] || :phoenix)}
  end

  test "takes no browser without a Playwright session", %{session: session} do
    session
    |> visit("/live/fluffy")
    |> assert(visible(by_text("Guardian head count: 0")))

    refute holds_lease?()
  end

  @tag backend: :playwright
  test "takes the test's browser for a Playwright session", %{session: session} do
    assert Fluffy.Session.current_driver(session) == :playwright
    assert holds_lease?()
  end

  defp holds_lease? do
    pool = Process.whereis(PlaywrightEx.Test.Pool)
    pool != nil and Map.has_key?(:sys.get_state(pool).scopes, self())
  end
end

defmodule Fluffy.CaseWithPlaywrightExTestTest do
  use ExUnit.Case, async: true
  use Fluffy.Case
  use PlaywrightEx.Test

  test "registers the test once" do
    assert PlaywrightEx.Test.info().test_pid == self()
  end
end

defmodule Fluffy.CaseWithoutCaseTest do
  # Phoenix sessions need nothing of Fluffy.Case.
  use ExUnit.Case, async: true

  test "runs Phoenix sessions and rejects Playwright ones" do
    Fluffy.start_session(:phoenix, endpoint: Fluffy.Support.Web.Endpoint)

    assert_raise RuntimeError, ~r/use Fluffy.Case/, fn ->
      Fluffy.start_session(:playwright, base_url: Fluffy.Support.Server.base_url())
    end
  end
end
