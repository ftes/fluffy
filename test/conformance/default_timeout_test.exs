defmodule Fluffy.Conformance.DefaultTimeoutTest do
  # As in Playwright Test, the defaults are PlaywrightEx's config, which is global.
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Session
  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  @action_timeout 3_000
  @navigation_timeout 1_000
  @expect_timeout 500
  @missing by_role(:button, name: "Missing")
  @appeared by_role(:button, name: "Appeared")

  # PlaywrightEx.Test sets each context's defaults when a test registers, in its `setup`.
  setup_all do
    put_playwright_ex_config(:test, action_timeout: @action_timeout, navigation_timeout: @navigation_timeout)
    put_playwright_ex_config(:expect, timeout: @expect_timeout)
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "actions default to action_timeout and expectations to the expect timeout with #{driver}",
         %{driver: driver} do
      session = missing_session(driver)

      elapsed = failure_time(fn -> expect(session, to_be_visible(@missing)) end)
      assert elapsed >= @expect_timeout - 100
      assert elapsed < @action_timeout

      elapsed = failure_time(fn -> click(session, @missing) end)
      assert elapsed >= @action_timeout - 100
      assert elapsed < @action_timeout + 3_000
    end

    @tag driver: driver
    test "a per-call timeout overrides the default with #{driver}", %{driver: driver} do
      session = missing_session(driver)

      assert failure_time(fn -> click(session, @missing, timeout: 200) end) < @action_timeout - 100
      assert failure_time(fn -> expect(session, to_be_visible(@missing, timeout: 1_500)) end) >= 1_400
    end

    # The button renders after the expect timeout, so only `:infinity` waits for it.
    @tag driver: driver
    test "timeout: :infinity waits past the default with #{driver}", %{driver: driver} do
      driver
      |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
      |> visit("/live/async?delay=#{@expect_timeout + 300}")
      |> expect(to_be_visible(@appeared), timeout: :infinity)
      |> click(@appeared, timeout: :infinity)
      |> expect("Activated" |> by_text() |> to_be_visible(timeout: :infinity))
    end

    @tag driver: driver
    test "timeout: 0 checks an expectation once with #{driver}", %{driver: driver} do
      session =
        driver
        |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
        |> visit("/live/async?delay=300")

      assert failure_time(fn -> expect(session, to_be_visible(@appeared), timeout: 0) end) < 300
    end
  end

  @tag driver: :live
  test "LiveView actions check once with timeout: 0" do
    session = missing_session(:phoenix)
    assert failure_time(fn -> click(session, @missing, timeout: 0) end) < 300
  end

  # As in Playwright, a route that never answers leaves the navigation to its timeout.
  @tag driver: :playwright
  test "navigations default to navigation_timeout" do
    session = start_session(:playwright, base_url: Server.base_url())
    fixture = HTTPFixtures.register(fn _request -> %{body: "<h1>Never</h1>"} end)
    Fluffy.Playwright.route(session, "**/never", fn _route -> :ok end)

    started = System.monotonic_time(:millisecond)
    error = assert_raise Fluffy.OperationError, fn -> visit(session, HTTPFixtures.path(fixture, "/never")) end
    assert %PlaywrightEx.TimeoutError{} = error.cause
    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed >= @navigation_timeout - 100
    assert elapsed < @action_timeout
  end

  # PlaywrightEx.Test sets them on the context: a native call gets them too.
  @tag driver: :playwright
  test "native calls get the context's defaults" do
    session = start_session(:playwright)
    started = System.monotonic_time(:millisecond)

    assert {:error, %PlaywrightEx.TimeoutError{}} =
             Fluffy.unwrap_and_return(session, &PlaywrightEx.Page.wait_for_url(&1, "**/never"))

    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed >= @navigation_timeout - 100
    assert elapsed < @action_timeout
  end

  @tag driver: :playwright
  test "a timeout too short for Playwright's bookkeeping limits only the operation" do
    session = start_session(:playwright)

    assert_raise Fluffy.OperationError, ~r/wait_for.*Timeout 1ms/s, fn ->
      wait_for(session, by_css("#missing"), timeout: 1)
    end
  end

  @tag driver: :playwright
  test "Playwright navigation bookkeeping does not depend on a short action timeout" do
    :playwright
    |> session_for_html(~s|<a href="/chamber">Chamber</a>|)
    |> click(by_role(:link, name: "Chamber"), timeout: 500)
    |> reload(timeout: 5_000)
    |> Fluffy.Playwright.go_back(timeout: 5_000)
    |> expect(page_to_have_url("/harness"), timeout: 5_000)
  end

  # No visit on Playwright: a navigation would share the budget under test on a loaded machine.
  defp missing_session(:playwright), do: start_session(:playwright)

  defp missing_session(:phoenix) do
    session =
      :phoenix
      |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
      |> visit("/live/chamber-map")

    assert Session.current_driver(session) == :live
    session
  end

  defp failure_time(operation) do
    started = System.monotonic_time(:millisecond)

    outcome =
      try do
        operation.()
      rescue
        error in [ExUnit.AssertionError, Fluffy.OperationError, Fluffy.ActionabilityError] -> error
      end

    assert is_exception(outcome)
    System.monotonic_time(:millisecond) - started
  end
end
