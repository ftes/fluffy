defmodule Fluffy.Conformance.BlockedPageTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Playwright

  @moduletag driver: :playwright

  @html "<button>Other</button>"

  # Calls that, as in Playwright, have no timeout wait on a blocked page until the test
  # times out if Fluffy calls Playwright directly (page `evaluate`, a context setter,
  # `unroute_all`). The others, `content` among them, first make Fluffy's bounded
  # document check.

  test "an action on a blocked page fails within the session timeout" do
    session = frozen_session()
    started = System.monotonic_time(:millisecond)

    assert_raise RuntimeError, ~r/did not respond to Fluffy's document check within 1000ms; .* a dialog/, fn ->
      click(session, by_role(:button, name: "Other"))
    end

    # The session timeout bounds the failure.
    assert System.monotonic_time(:millisecond) - started < 10_000

    # The abandoned call leaves the driver connection usable.
    assert Playwright.evaluate(session_for_html(:playwright, "<p>ok</p>"), "1 + 1") == 2
  end

  test "a blocked page on a sub-second session reports after a second" do
    session = put_session_timeout(frozen_session(), 100)

    assert_raise RuntimeError, ~r/document check within 1000ms/, fn ->
      click(session, by_role(:button, name: "Other"))
    end
  end

  test "a call without a timeout fails at the document check on a page already blocked" do
    session = frozen_session()

    assert_raise RuntimeError, ~r/did not respond to Fluffy's document check within 1000ms/, fn ->
      Playwright.content(session)
    end
  end

  test "a blocked page that page code navigated reports its URL without waiting for the page" do
    session =
      :playwright |> session_for_html(@html, base_url: Fluffy.TestServer.base_url()) |> put_session_timeout(1_000)

    Playwright.evaluate(session, "history.pushState(null, '', 'pushed')")
    freeze_page(session)

    # Waiting for the page under this timeout would outlast the test's own.
    session = put_session_timeout(session, 600_000)
    assert session |> Playwright.current_page() |> Fluffy.Page.url() |> String.ends_with?("/pushed")
  end

  defp frozen_session do
    :playwright
    |> session_for_html(@html, base_url: Fluffy.TestServer.base_url())
    |> put_session_timeout(1_000)
    |> freeze_page()
  end
end
