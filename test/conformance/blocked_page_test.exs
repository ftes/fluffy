defmodule Fluffy.Conformance.BlockedPageTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Playwright

  @moduletag :tmp_dir
  @moduletag driver: :playwright

  @html "<button>Other</button>"

  test "an action on a blocked page fails within the session timeout" do
    session = frozen_session()
    started = System.monotonic_time(:millisecond)

    assert_raise RuntimeError, ~r/did not respond to Fluffy's document check within 1000ms; .* a dialog/, fn ->
      click(session, by_role(:button, name: "Other"))
    end

    # The session timeout bounds the failure. Failure artifacts (captured when
    # an artifact dir is configured, as in CI) add up to 4s of bounded waits.
    assert System.monotonic_time(:millisecond) - started < 10_000

    # The abandoned call leaves the driver connection usable.
    assert Playwright.evaluate(session_for_html(:playwright, "<p>ok</p>"), "1 + 1") == 2
  end

  test "evaluate of a never-settling expression fails within the session timeout" do
    session = :playwright |> session_for_html("<p>ok</p>", base_url: Fluffy.TestServer.base_url()) |> short_timeout()
    started = System.monotonic_time(:millisecond)

    assert_raise RuntimeError, ~r/evaluate did not finish within 1000ms/, fn ->
      Playwright.evaluate(session, "() => new Promise(() => {})")
    end

    assert System.monotonic_time(:millisecond) - started < 5_000
    assert Playwright.evaluate(session, "1 + 1") == 2
  end

  test "a PhoenixTest CSS link probe on a blocked page fails within the session timeout" do
    session = frozen_session()
    started = System.monotonic_time(:millisecond)

    assert_raise Fluffy.OperationError, ~r/click_link failed.*Timeout 1000ms exceeded while counting matches/s, fn ->
      Fluffy.PhoenixTest.click_link(session, "a", "Other")
    end

    assert System.monotonic_time(:millisecond) - started < 10_000
  end

  # Browsers close a blocked page today; the session timeout bounds it if one waits.
  test "closing a blocked page is bounded by the session timeout" do
    session = frozen_session()
    page = Playwright.current_page(session)
    started = System.monotonic_time(:millisecond)

    try do
      Playwright.close_page(session, page)
    rescue
      error in RuntimeError -> assert error.message =~ "close_page did not finish within 1000ms"
    end

    assert System.monotonic_time(:millisecond) - started < 10_000
  end

  for {operation, setter} <- [
        grant_permissions: quote(do: &Playwright.grant_permissions(&1, ["geolocation"])),
        clear_permissions: quote(do: &Playwright.clear_permissions/1),
        set_geolocation: quote(do: &Playwright.set_geolocation(&1, %{latitude: 1, longitude: 2})),
        set_offline: quote(do: &Playwright.set_offline(&1, true)),
        set_http_credentials: quote(do: &Playwright.set_http_credentials(&1, %{username: "u", password: "p"}))
      ] do
    # Which setters a blocked page holds up differs per browser.
    test "#{operation} on a blocked page is bounded by the session timeout" do
      session = frozen_session()
      started = System.monotonic_time(:millisecond)

      try do
        assert unquote(setter).(session) == session
      rescue
        error in RuntimeError -> assert error.message =~ "#{unquote(operation)} did not finish within 1000ms"
      end

      assert System.monotonic_time(:millisecond) - started < 5_000
    end
  end

  test "a context setter a blocked page holds up raises within the session timeout" do
    session = frozen_session()
    started = System.monotonic_time(:millisecond)

    if playwright_engine?(:firefox) do
      assert_raise RuntimeError, ~r/grant_permissions did not finish within 1000ms/, fn ->
        Playwright.grant_permissions(session, ["geolocation"])
      end
    else
      assert_raise RuntimeError, ~r/set_offline did not finish within 1000ms/, fn ->
        Playwright.set_offline(session, true)
      end
    end

    assert System.monotonic_time(:millisecond) - started < 5_000
  end

  test "a blocked page that page code navigated reports its URL without waiting for the page" do
    session = :playwright |> session_for_html(@html, base_url: Fluffy.TestServer.base_url()) |> short_timeout()
    Playwright.evaluate(session, "history.pushState(null, '', 'pushed')")

    assert_raise RuntimeError, ~r/evaluate did not finish within 1000ms/, fn ->
      Playwright.evaluate(session, "() => { while (true) {} }")
    end

    # Waiting for the page under this timeout would outlast the test's own.
    session = Fluffy.Session.put_context(session, %{Fluffy.Session.context(session) | timeout: 600_000})
    assert session |> Playwright.current_page() |> Fluffy.Page.url() |> String.ends_with?("/pushed")
  end

  test "failure artifacts of a blocked page are captured without waiting for it", %{tmp_dir: tmp_dir} do
    session = frozen_session()
    started = System.monotonic_time(:millisecond)

    assert Fluffy.FailureArtifact.capture(session, :click, RuntimeError.exception("boom"), [], tmp_dir) == :ok
    assert [_report] = Path.wildcard(Path.join(tmp_dir, "*.txt"))
    assert System.monotonic_time(:millisecond) - started < 10_000
  end

  defp frozen_session do
    session = :playwright |> session_for_html(@html, base_url: Fluffy.TestServer.base_url()) |> short_timeout()

    # The freeze runs inside the evaluate, so it is in place before any later
    # Fluffy call reaches the page; the abandoned evaluate keeps it blocked.
    assert_raise RuntimeError, ~r/evaluate did not finish within 1000ms/, fn ->
      Playwright.evaluate(session, "() => { while (true) {} }")
    end

    session
  end

  # Setup (visit, LiveView join, set_html) runs under the default timeout so a
  # loaded machine cannot fail it; only the blocked part runs under 1s. No
  # public API changes a live session's timeout, so this uses the internal one.
  defp short_timeout(session) do
    Fluffy.Session.put_context(session, %{Fluffy.Session.context(session) | timeout: 1_000})
  end
end
