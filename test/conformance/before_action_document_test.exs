defmodule Fluffy.Conformance.BeforeActionDocumentTest do
  # What an action must know before it runs: the document it acts on and the
  # LiveView navigations already behind it. Each test first runs an action, so
  # the action under test could lean on that earlier read, then changes the
  # page in a way the earlier read cannot know about.
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.Session
  alias Fluffy.TestWeb.Endpoint
  alias PlaywrightEx.Page, as: BrowserPage

  @moduletag driver: :playwright

  @map "/live/chamber-map"
  # Connects slowly, so a click that does not wait for the join is lost.
  @slow_map "/live/chamber-map?delay=400"
  @note "Map note"
  @rest "The guardian sleeps"

  defp expect_live_document(session) do
    session
    |> click(by_role(:button, name: "Patch now"))
    |> expect(page_to_have_url(@map <> "?step=patched"))
  end

  defp live_session, do: start_session(:playwright, base_url: Fluffy.TestServer.base_url(), endpoint: Endpoint)

  defp fill_note(session), do: fill(session, by_label(@note), "note #{System.unique_integer([:positive])}")

  defp rest_click(session), do: click(session, by_text(@rest))

  # The page's own navigation, on a timer so it follows the previous action.
  defp schedule(session, script), do: tap(session, &evaluate(&1, "() => { setTimeout(() => { #{script} }, 30) }"))

  # Waits for a URL without Fluffy reading the page, unlike expect/2.
  defp await_url(session, part) do
    :ok =
      BrowserPage.wait_for_url(Session.page_state(session).page, &String.contains?(to_string(&1), part),
        wait_until: :commit,
        timeout: 5_000
      )

    session
  end

  describe "a navigation inside unwrap" do
    test "as the first thing a session does is adopted by the next action" do
      live_session()
      |> unwrap(fn page -> BrowserPage.goto!(page, @slow_map) end)
      |> expect_live_document()
    end

    test "after an action is adopted by the next action" do
      live_session()
      |> visit("/chamber")
      |> rest_click()
      |> unwrap(fn page -> BrowserPage.goto!(page, @slow_map) end)
      |> expect_live_document()
    end
  end

  describe "a navigation after the previous action returned" do
    test "a late redirect from page code is adopted by the next action" do
      live_session()
      |> visit(@map)
      |> fill_note()
      |> schedule("location.href = '#{@slow_map}&step=redirected'")
      |> await_url("step=redirected")
      |> expect_live_document()
    end

    test "a document replaced by a native call outside unwrap is adopted by the next action" do
      session = live_session() |> visit("/chamber") |> rest_click()
      BrowserPage.goto!(Session.page_state(session).page, @slow_map)
      expect_live_document(session)
    end

    test "a same-document URL change from page code is read again by the next action" do
      live_session()
      |> visit("/chamber")
      |> rest_click()
      |> schedule("history.replaceState(null, '', '/chamber?replaced=1')")
      |> await_url("replaced=1")
      |> rest_click()
      |> expect(page_to_have_url("/chamber?replaced=1"))
    end

    test "a hash navigation from page code is read again by the next action" do
      live_session()
      |> visit("/chamber")
      |> rest_click()
      |> schedule("location.hash = 'den'")
      |> await_url("#den")
      |> rest_click()
      |> expect(page_to_have_url("/chamber#den"))
    end
  end

  describe "a new page" do
    test "a popup's first document waits for its LiveView after the opener acted" do
      session = live_session() |> visit(@map <> "?topic=popup-before-action") |> fill_note()

      pending = wait_for(session, Event.popup())
      click(session, by_role(:link, name: "Open ready popup"))
      popup = switch_page(session, await(pending))

      click(popup, by_text("Redirect-ready LiveView", exact: true))
      :ok = Phoenix.PubSub.broadcast(Fluffy.TestPubSub, "popup-before-action", {:redirect_ready, "joined"})
      expect(popup, "Broadcast: joined" |> by_text(exact: true) |> to_be_visible())
    end

    test "a page's later navigation is adopted once it has acted" do
      session =
        session_for_html(:playwright, ~s|<button onclick="window.open('/chamber', 'p')">Open</button>|,
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Endpoint
        )

      pending = wait_for(session, Event.popup())
      click(session, by_role(:button, name: "Open"))
      popup = switch_page(session, await(pending))

      popup
      |> rest_click()
      |> schedule("location.href = '#{@slow_map}'")
      |> await_url("delay=400")
      |> expect_live_document()
    end
  end

  describe "a LiveView navigation that changes no URL" do
    test "a patch to the current URL leaves later actions working" do
      session =
        live_session()
        |> visit(@map <> "?step=late-patched")
        |> click(by_role(:button, name: "Reveal passage after event"))

      # The server patches 30ms later, to the URL the page already has.
      Process.sleep(200)

      session
      |> fill_note()
      |> expect(page_to_have_url(@map <> "?step=late-patched"))
      |> expect_live_document()
    end

    test "a redirect to the current URL replaces the view for later actions" do
      session =
        live_session()
        |> visit(@map)
        |> click(by_role(:button, name: "Re-enter map after event"))

      # The server redirects 30ms later, to the URL the page already has.
      Process.sleep(200)

      session
      |> fill_note()
      |> expect(page_to_have_url(@map))
      |> expect_live_document()
    end

    test "a redirect already behind the cursor does not fail the next action" do
      session =
        live_session()
        |> visit(@map)
        |> fill_note()
        |> schedule("""
        const to = location.href
        window.dispatchEvent(new CustomEvent('phx:page-loading-start', {detail: {kind: 'redirect', to}}))
        window.dispatchEvent(new CustomEvent('phx:page-loading-stop', {detail: {kind: 'redirect', to}}))
        """)

      Process.sleep(200)

      session
      |> fill_note()
      |> expect(page_to_have_url(@map))
      |> expect_live_document()
    end

    test "a patch under way when the next action runs is waited for" do
      session =
        live_session()
        |> visit(@map)
        |> fill_note()
        |> schedule("""
        const to = location.href + '?step=loading'
        window.dispatchEvent(new CustomEvent('phx:page-loading-start', {detail: {kind: 'patch', to}}))
        setTimeout(() => {
          history.pushState(null, '', to)
          window.dispatchEvent(new CustomEvent('phx:page-loading-stop', {detail: {kind: 'patch', to}}))
        }, 200)
        """)

      Process.sleep(60)

      session
      |> fill_note()
      |> expect(page_to_have_url(@map <> "?step=loading"))
    end
  end

  describe "when the earlier read is missing" do
    test "a navigation during a failed action is adopted by the next action" do
      session =
        live_session()
        |> visit("/chamber")
        |> rest_click()
        |> schedule("location.href = '#{@slow_map}'")

      assert_raise Fluffy.OperationError, fn ->
        click(session, by_role(:button, name: "Not on either page"), timeout: 300)
      end

      expect_live_document(session)
    end
  end
end
