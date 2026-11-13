defmodule Fluffy.Conformance.DefaultTimeoutTest do
  # As in Playwright Test, the defaults are config, which is global: only what needs other
  # defaults than the suite's is here, the rest passes `timeout:`
  # (`Fluffy.Conformance.TimeoutOptionTest`). Fluffy's `action_timeout` and `expect_timeout` win
  # over PlaywrightEx's; unset, PlaywrightEx's apply, and its navigation timeout always does.
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Session
  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  # Short, as the tests wait them out, and apart, so the time a failure took tells which one
  # applied. PlaywrightEx's are shorter than Fluffy's.
  @action_timeout 600
  @expect_timeout 200
  @navigation_timeout 400
  @playwright_ex_timeout 100
  # A failure comes at its timeout or later, give or take a timer's precision.
  @early 50
  @missing by_role(:button, name: "Missing")
  @appeared by_role(:button, name: "Appeared")

  # `visit` takes no `timeout:`: the visits of these tests get a long default, and the
  # navigation tests set theirs. PlaywrightEx.Test sets its timeouts on each context when a test
  # registers, in its `setup`, and a Fluffy session the resolved ones when it starts.
  setup_all do
    put_fluffy_config(action_timeout: @action_timeout, expect_timeout: @expect_timeout)
    put_playwright_ex_config(:test, action_timeout: @playwright_ex_timeout, navigation_timeout: 5_000)
    put_playwright_ex_config(:expect, timeout: @playwright_ex_timeout)
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "actions default to Fluffy's action_timeout and expectations to its expect_timeout, over PlaywrightEx's, with #{driver}",
         %{driver: driver} do
      session = missing_session(driver)

      {elapsed, error} = failure(fn -> expect(session, to_be_visible(@missing)) end)
      assert elapsed >= @expect_timeout - @early
      if driver == :playwright, do: assert(error.message =~ "Timeout: #{@expect_timeout}ms")
      assert elapsed < @action_timeout

      {elapsed, error} = failure(fn -> click(session, @missing) end)
      assert elapsed >= @action_timeout - @early
      if driver == :playwright, do: assert(error.message =~ "Timeout #{@action_timeout}ms exceeded.")
    end

    @tag driver: driver
    test "unset, Fluffy's timeouts fall back to PlaywrightEx's with #{driver}", %{driver: driver} do
      put_fluffy_config(action_timeout: nil, expect_timeout: nil)
      session = missing_session(driver)

      {elapsed, error} = failure(fn -> expect(session, to_be_visible(@missing)) end)
      assert elapsed in (@playwright_ex_timeout - @early)..5_000
      if driver == :playwright, do: assert(error.message =~ "Timeout: #{@playwright_ex_timeout}ms")

      {elapsed, error} = failure(fn -> click(session, @missing) end)
      assert elapsed in (@playwright_ex_timeout - @early)..5_000
      if driver == :playwright, do: assert(error.message =~ "Timeout #{@playwright_ex_timeout}ms exceeded.")
    end

    # PlaywrightEx's `0` means no limit, as in Playwright, not Fluffy's check once: the button
    # renders after PlaywrightEx's other timeouts.
    @tag driver: driver
    test "PlaywrightEx's timeouts of 0 mean no limit with #{driver}", %{driver: driver} do
      put_fluffy_config(action_timeout: nil, expect_timeout: nil)
      put_playwright_ex_config(:test, action_timeout: 0)
      put_playwright_ex_config(:expect, timeout: 0)

      driver
      |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
      |> visit("/live/async?delay=#{@playwright_ex_timeout + 300}")
      |> expect(to_be_visible(@appeared))
      |> click(@appeared)
      |> expect("Activated" |> by_text() |> to_be_visible())
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

    # Set before the session starts: a Playwright session sets it on its context then. The
    # button renders after the action timeout.
    @tag driver: driver
    test "action_timeout: :infinity waits past the default with #{driver}", %{driver: driver} do
      put_fluffy_config(action_timeout: :infinity, expect_timeout: :infinity)

      driver
      |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
      |> visit("/live/async?delay=#{@action_timeout + 100}")
      |> click(@appeared)
      |> expect("Activated" |> by_text() |> to_be_visible())
    end

    # As a call's `timeout: 0`; Playwright's 0 would wait for the button.
    @tag driver: driver
    test "expect_timeout: 0 checks expectations once with #{driver}", %{driver: driver} do
      put_fluffy_config(expect_timeout: 0)

      session =
        driver
        |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
        |> visit("/live/async?delay=1000")

      {elapsed, _error} = failure(fn -> expect(session, to_be_visible(@appeared)) end)
      assert elapsed < 1_000
    end
  end

  # As in Playwright, a route that never answers leaves the navigation to its timeout.
  @tag driver: :playwright
  test "navigations default to PlaywrightEx's navigation_timeout" do
    put_playwright_ex_config(:test, navigation_timeout: @navigation_timeout)
    session = start_session(:playwright, base_url: Server.base_url())
    fixture = HTTPFixtures.register(fn _request -> %{body: "<h1>Never</h1>"} end)
    Fluffy.Playwright.route(session, "**/never", fn _route -> :ok end)

    {elapsed, error} = failure(fn -> visit(session, HTTPFixtures.path(fixture, "/never")) end)
    assert %PlaywrightEx.TimeoutError{message: message} = error.cause
    assert message =~ "Timeout #{@navigation_timeout}ms exceeded."
    assert elapsed >= @navigation_timeout - @early
  end

  # The session sets the resolved ones on its context, over what PlaywrightEx.Test set at
  # registration: a native call gets them too.
  @tag driver: :playwright
  test "native calls default to the resolved action and navigation timeouts" do
    put_playwright_ex_config(:test, navigation_timeout: @navigation_timeout)
    session = start_session(:playwright)

    {elapsed, error} =
      native_failure(fn -> Fluffy.Playwright.unwrap_and_return(session, @missing, &PlaywrightEx.Locator.click/1) end)

    assert error.message =~ "Timeout #{@action_timeout}ms exceeded."
    assert elapsed >= @action_timeout - @early

    {elapsed, error} =
      native_failure(fn -> Fluffy.unwrap_and_return(session, &PlaywrightEx.Page.wait_for_url(&1, "**/never")) end)

    assert error.message =~ "Timeout #{@navigation_timeout}ms exceeded."
    assert elapsed >= @navigation_timeout - @early
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

  defp failure(operation), do: timed(fn -> rescue_failure(operation) end)

  defp rescue_failure(operation) do
    operation.()
  rescue
    error in [ExUnit.AssertionError, Fluffy.OperationError, Fluffy.ActionabilityError] -> error
  else
    _result -> flunk("expected the operation to fail")
  end

  defp native_failure(operation) do
    timed(fn ->
      assert {:error, %PlaywrightEx.TimeoutError{} = error} = operation.()
      error
    end)
  end

  defp timed(fun) do
    started = System.monotonic_time(:millisecond)
    result = fun.()
    {System.monotonic_time(:millisecond) - started, result}
  end
end

defmodule Fluffy.Conformance.TimeoutOptionTest do
  # A call's `timeout:` over the suite's defaults (`config/test.exs`: 15 s for actions, 5 s for
  # expectations), which these tests never wait out.
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Session
  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  @timeout 300
  @early 50
  @missing by_role(:button, name: "Missing")
  @appeared by_role(:button, name: "Appeared")

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "a per-call timeout overrides the default with #{driver}", %{driver: driver} do
      session = missing_session(driver)

      {elapsed, error} = failure(fn -> click(session, @missing, timeout: @timeout) end)
      assert elapsed in (@timeout - @early)..5_000
      if driver == :playwright, do: assert(error.message =~ "Timeout #{@timeout}ms exceeded.")

      {elapsed, error} = failure(fn -> expect(session, to_be_visible(@missing, timeout: @timeout)) end)
      assert elapsed in (@timeout - @early)..5_000
      if driver == :playwright, do: assert(error.message =~ "Timeout: #{@timeout}ms")
    end

    # Playwright's 0 would wait for the button.
    @tag driver: driver
    test "timeout: 0 checks an expectation once with #{driver}", %{driver: driver} do
      session =
        driver
        |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
        |> visit("/live/async?delay=1000")

      {elapsed, _error} = failure(fn -> expect(session, to_be_visible(@appeared), timeout: 0) end)
      assert elapsed < 1_000
    end
  end

  @tag driver: :live
  test "LiveView actions check once with timeout: 0" do
    session = missing_session(:phoenix)
    {elapsed, _error} = failure(fn -> click(session, @missing, timeout: 0) end)
    assert elapsed < 1_000
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

  defp failure(operation) do
    started = System.monotonic_time(:millisecond)
    error = rescue_failure(operation)
    {System.monotonic_time(:millisecond) - started, error}
  end

  defp rescue_failure(operation) do
    operation.()
  rescue
    error in [ExUnit.AssertionError, Fluffy.OperationError, Fluffy.ActionabilityError] -> error
  else
    _result -> flunk("expected the operation to fail")
  end
end
