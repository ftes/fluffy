defmodule Fluffy.Conformance.BlockedPageTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Playwright

  @moduletag :tmp_dir
  @moduletag driver: :playwright

  @html "<button>Other</button>"

  # Calls that, as in Playwright, have no timeout (such as `evaluate`, `content` or a
  # context setter) wait on a blocked page until the test times out. Fluffy's own
  # document checks around an operation are bounded.

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

  test "a blocked page on a sub-second session reports after a second" do
    session = put_session_timeout(frozen_session(), 100)

    assert_raise RuntimeError, ~r/document check within 1000ms/, fn ->
      click(session, by_role(:button, name: "Other"))
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

  test "failure artifacts of a blocked page are captured without waiting for it", %{tmp_dir: tmp_dir} do
    session = frozen_session()
    started = System.monotonic_time(:millisecond)

    assert Fluffy.FailureArtifact.capture(session, :click, RuntimeError.exception("boom"), [], tmp_dir) == :ok
    assert [_report] = Path.wildcard(Path.join(tmp_dir, "*.txt"))
    assert System.monotonic_time(:millisecond) - started < 10_000
  end

  defp frozen_session do
    :playwright
    |> session_for_html(@html, base_url: Fluffy.TestServer.base_url())
    |> put_session_timeout(1_000)
    |> freeze_page()
  end
end
