defmodule Fluffy.Conformance.BlockedPageTest do
  # The default action timeout, which bounds Fluffy's document check, is global config.
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Playwright
  # Calls that, as in Playwright, have no timeout wait on a blocked page until the test
  # times out if Fluffy calls Playwright directly (page `evaluate`, a context setter,
  # `unroute_all`). The others, `content` among them, first make Fluffy's bounded
  # document check.
  alias Fluffy.Support.Server

  @moduletag driver: :playwright

  @html "<button>Other</button>"

  setup_all do
    put_fluffy_config(action_timeout: 1_000)
  end

  test "an action on a blocked page fails within the action timeout" do
    session = frozen_session()
    started = System.monotonic_time(:millisecond)

    assert_raise RuntimeError, ~r/did not respond to Fluffy's document check within 1000ms; .* a dialog/, fn ->
      click(session, by_role(:button, name: "Other"))
    end

    # The action timeout bounds the failure.
    assert System.monotonic_time(:millisecond) - started < 10_000

    # The abandoned call leaves the driver connection usable.
    assert Playwright.evaluate(session_for_html(:playwright, "<p>ok</p>"), "1 + 1") == 2
  end

  test "a blocked page with a sub-second timeout reports after a second" do
    session = frozen_session()

    assert_raise RuntimeError, ~r/document check within 1000ms/, fn ->
      click(session, by_role(:button, name: "Other"), timeout: 100)
    end
  end

  test "a call without a timeout fails at the document check on a page already blocked" do
    session = frozen_session()

    assert_raise RuntimeError, ~r/did not respond to Fluffy's document check within 1000ms/, fn ->
      Playwright.content(session)
    end
  end

  test "a blocked page that page code navigated reports its URL without waiting for the page" do
    session = session_for_html(:playwright, @html, base_url: Server.base_url())

    Playwright.evaluate(session, "history.pushState(null, '', 'pushed')")
    freeze_page(session)

    # Waiting for the page would raise after the action timeout.
    assert session |> Playwright.current_page() |> Fluffy.Page.url() |> String.ends_with?("/pushed")
  end

  defp frozen_session do
    :playwright
    |> session_for_html(@html, base_url: Server.base_url())
    |> freeze_page()
  end
end
