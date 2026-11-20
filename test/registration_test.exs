defmodule Fluffy.RegistrationTest do
  # Playwright.Test registers the test; the imports and the session are the module's own.
  use ExUnit.Case, async: true
  use Playwright.Test

  test "imports nothing of Fluffy and starts no session", context do
    refute Map.has_key?(context, :session)
    refute Keyword.has_key?(__ENV__.functions, Fluffy)
    refute Keyword.has_key?(__ENV__.functions, Fluffy.Locator)
    assert Playwright.Test.info().test_pid == self()
  end

  @tag timeout: 30_000
  test "bounds Phoenix waits by the test's timeout" do
    assert {30_000, _backstop} = Fluffy.TestTimeout.fetch()
  end
end

defmodule Fluffy.RegistrationNativeTest do
  use ExUnit.Case, async: true
  use Playwright.Test
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

defmodule Fluffy.RegistrationPhoenixTestFacadeTest do
  # The facade's names don't clash with what Playwright.Test imports.
  use ExUnit.Case, async: true
  use Playwright.Test

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

defmodule Fluffy.RegistrationTest.FeatureCase do
  # The recommended template: registered in its body, before its own setups, and again in
  # `using`, which only brings the `test` macro then.
  @moduledoc false
  use ExUnit.CaseTemplate
  use Playwright.Test

  using do
    quote do
      use Playwright.Test
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

defmodule Fluffy.RegistrationTemplateTest do
  use Fluffy.RegistrationTest.FeatureCase, async: true

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

defmodule Fluffy.RegistrationBrowserLeaseTest do
  # A test takes a browser from Playwright.Test's pool, and with it one of `workers`
  # seats, only for a Playwright session. The pool has no public view of its seats, so this
  # reads its state: the scopes that hold seats, here the test process, until the test's `on_exit`.
  use ExUnit.Case, async: true
  use Playwright.Test
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
    pool = Process.whereis(Playwright.Test.Pool)
    pool != nil and Map.has_key?(:sys.get_state(pool).scopes, self())
  end
end

defmodule Fluffy.RegistrationSetupAllTest do
  # `setup_all` is registered too (`Playwright.Test.info/0` works there), but a session belongs to
  # a test, as Playwright Test's `page` fixture, which `beforeAll` can't use.
  use ExUnit.Case, async: true
  use Playwright.Test

  setup_all do
    for backend <- [:phoenix, :playwright] do
      assert_raise RuntimeError, ~r/not in its setup_all/, fn ->
        Fluffy.start_session(backend, endpoint: Fluffy.Support.Web.Endpoint)
      end
    end

    %{setup_all_timeout: Fluffy.TestTimeout.fetch()}
  end

  test "starts no session in setup_all, which has no test backstop", %{setup_all_timeout: timeout} do
    assert timeout == nil
  end
end

defmodule Fluffy.UnregisteredTest do
  # Every session belongs to a registered test.
  use ExUnit.Case, async: true

  test "starts no session outside a registered test" do
    for backend <- [:phoenix, :playwright] do
      assert_raise RuntimeError, ~r/in a test of a module with `use Playwright.Test`/, fn ->
        Fluffy.start_session(backend, endpoint: Fluffy.Support.Web.Endpoint)
      end
    end
  end
end
