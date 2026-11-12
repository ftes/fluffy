defmodule Fluffy.CaseTest do
  use ExUnit.Case, async: true
  use Fluffy.Case

  # Before Fluffy.Case's session setup.
  setup {Fluffy.Support.Case, :exclusive_firefox}

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

defmodule Fluffy.CaseWithPlaywrightExTestTest do
  # A second `use PlaywrightEx.Test` registers no second setup, which would raise.
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
