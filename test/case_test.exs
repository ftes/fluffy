defmodule Fluffy.CaseTest do
  use ExUnit.Case, async: true
  use Fluffy.Case

  test "starts a Phoenix session by default", %{session: session} do
    session
    |> visit("/live/fluffy")
    |> assert(visible(by_text("Guardian head count: 0")))

    assert Fluffy.Session.current_driver(session) == :live
  end

  @tag backend: :playwright
  test "starts the session of the tagged backend", %{session: session} do
    session
    |> visit("/live/fluffy")
    |> assert(visible(by_text("Guardian head count: 0")))

    assert Fluffy.Session.current_driver(session) == :playwright
  end
end

defmodule Fluffy.CaseBrowserLeaseTest do
  # A test takes a browser from PlaywrightEx.Test's pool, and with it one of `workers`
  # seats, only for a Playwright session. The pool has no public view of its seats, so this
  # reads its state: the scopes that hold seats, here the test process, until the test's `on_exit`.
  use ExUnit.Case, async: true
  use Fluffy.Case

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

  test "registers the test once", %{session: session} do
    assert PlaywrightEx.Test.info().test_pid == self()
    assert %Fluffy.Session{} = session
  end
end

defmodule Fluffy.CaseWithoutPlaywrightExTestTest do
  # Phoenix sessions need nothing of PlaywrightEx.Test.
  use ExUnit.Case, async: true

  test "runs Phoenix sessions and rejects Playwright ones" do
    Fluffy.start_session(:phoenix, endpoint: Fluffy.Support.Web.Endpoint)

    assert_raise RuntimeError, ~r/use PlaywrightEx.Test/, fn ->
      Fluffy.start_session(:playwright, base_url: Fluffy.Support.Server.base_url())
    end
  end
end
