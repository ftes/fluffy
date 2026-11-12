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

    # A second `use Fluffy.Test` registers no second setup, which would raise.
    assert Fluffy.Session.current_driver(session) == :playwright
  end
end

defmodule Fluffy.CaseWithFluffyTestTest do
  use ExUnit.Case, async: true
  use Fluffy.Case
  use Fluffy.Test

  test "sets up the test once", %{session: session} do
    assert %{test_context: %{test: test}} = Fluffy.TestScope.current()
    assert test == :"test sets up the test once"
    assert %Fluffy.Session{} = session
  end
end
