defmodule Fluffy.Conformance.BlockedPageTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  @moduletag :tmp_dir
  @moduletag driver: :playwright

  # The click returns before its timer blocks the main thread; the next action's
  # document check then meets a page that never answers.
  @html """
  <button onclick="setTimeout(() => { while (true) {} }, 50)">Freeze</button>
  <button>Other</button>
  """

  test "an action on a blocked page fails within the session timeout" do
    session = frozen_session()
    started = System.monotonic_time(:millisecond)

    assert_raise RuntimeError, ~r/did not respond to Fluffy's document check within 1000ms; .* a dialog/, fn ->
      click(session, by_role(:button, name: "Other"))
    end

    assert System.monotonic_time(:millisecond) - started < 5_000

    # The abandoned call leaves the driver connection usable.
    assert Fluffy.Playwright.evaluate(session_for_html(:playwright, "<p>ok</p>"), "1 + 1") == 2
  end

  test "evaluate of a never-settling expression fails within the session timeout" do
    session = session_for_html(:playwright, "<p>ok</p>", base_url: Fluffy.TestServer.base_url(), timeout: 1_000)
    started = System.monotonic_time(:millisecond)

    assert_raise RuntimeError, ~r/evaluate did not finish within 1000ms/, fn ->
      Fluffy.Playwright.evaluate(session, "() => new Promise(() => {})")
    end

    assert System.monotonic_time(:millisecond) - started < 5_000
    assert Fluffy.Playwright.evaluate(session, "1 + 1") == 2
  end

  test "failure artifacts of a blocked page are captured without waiting for it", %{tmp_dir: tmp_dir} do
    session = frozen_session()
    started = System.monotonic_time(:millisecond)

    assert Fluffy.FailureArtifact.capture(session, :click, RuntimeError.exception("boom"), [], tmp_dir) == :ok
    assert [_report] = Path.wildcard(Path.join(tmp_dir, "*.txt"))
    assert System.monotonic_time(:millisecond) - started < 10_000
  end

  defp frozen_session do
    session = session_for_html(:playwright, @html, base_url: Fluffy.TestServer.base_url(), timeout: 1_000)
    session = click(session, by_role(:button, name: "Freeze"))
    Process.sleep(200)
    session
  end
end
