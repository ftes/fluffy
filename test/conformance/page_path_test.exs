defmodule Fluffy.Conformance.PagePathTest do
  use Fluffy.Support.Case, async: true
  use Fluffy.Assert

  import Fluffy

  for driver <- Drivers.backends(), path <- ["/chamber", "/live/chamber-map"] do
    @tag driver: driver
    test "matches the exact path and optional decoded query on #{path} with #{driver}", %{driver: driver} do
      path = unquote(path)
      query = "state=brewing&page=2&name=Polyjuice+Potion&tag=old&tag=new&empty="

      driver
      |> start_session()
      |> visit(path <> "?" <> query <> "#summary")
      |> assert(page_path(path))
      |> assert(page_path(path, params: %{"name" => "Polyjuice Potion", page: 2, state: :brewing}))
      |> assert(page_path(path, params: &(&1["tag"] == "new" and &1["empty"] == "")))
      |> refute(page_path(path <> "/", params: %{state: "brewing"}), timeout: :once)
      |> refute(page_path(path, params: %{state: "finished"}), timeout: :once)
    end

    @tag driver: driver
    test "reports the expected path and params on #{path} with #{driver}", %{driver: driver} do
      path = unquote(path)

      session =
        driver
        |> start_session()
        |> visit(path <> "?state=brewing")

      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert(session, page_path(path, params: %{state: "finished"}, timeout: :once))
        end

      assert error.message =~ "path #{inspect(path)} with params %{state: \"finished\"}"
      assert error.message =~ "#{path}?state=brewing"

      error =
        assert_raise ExUnit.AssertionError, fn ->
          refute(session, page_path(path, params: %{state: "brewing"}), timeout: :once)
        end

      assert error.message =~ "not active page to have path #{inspect(path)}"
    end
  end

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "treats absent and empty queries as an empty map with #{driver}", %{driver: driver} do
      driver
      |> start_session()
      |> visit("/chamber")
      |> assert(page_path("/chamber", params: &(&1 == %{})))
      |> visit("/chamber?#summary")
      |> assert(page_path("/chamber", params: &(&1 == %{})))
    end
  end

  @tag driver: :playwright
  test "waits for the path and query to match on the same navigation" do
    session = :playwright |> start_session() |> visit("/chamber?state=brewing")

    Fluffy.Playwright.evaluate(session, """
    setTimeout(() => history.replaceState(null, '', '/potions?state=finished'), 100)
    """)

    refute(session, page_path("/chamber", params: %{state: "finished"}), timeout: :once)

    Fluffy.Playwright.evaluate(session, """
    setTimeout(() => history.replaceState(null, '', '/chamber?state=finished'), 200)
    """)

    session = assert(session, page_path("/chamber", params: %{state: "finished"}), timeout: 2_000)
    assert(session, page_url("/chamber?state=finished"), timeout: :once)
  end
end
