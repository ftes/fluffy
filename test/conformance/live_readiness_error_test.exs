defmodule Fluffy.Conformance.LiveReadinessErrorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Playwright

  @tag driver: :playwright
  test "a parent patch does not make a connected nested LiveView unready" do
    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url(), timeout: 1_000)
      |> visit("/live/nested")
      |> fill(by_label("Parent email"), "parent@example.com")
      |> click(by_role(:button, name: "Save parent"))
      |> expect("Parent saved: parent@example.com" |> by_text() |> to_be_visible())

    # Parent patches can strip this class. Keep the regression deterministic if
    # a future LiveView release preserves it, and do not rely on a global socket.
    Playwright.evaluate(session, """
    document.getElementById('nested-child').classList.remove('phx-connected');
    delete window.liveSocket;
    """)

    session
    |> visit("/live/nested#after-parent-patch")
    |> click(by_role(:button, name: "Increment child"))
    |> expect("Child count: 1" |> by_text() |> to_be_visible())
  end

  @tag driver: :playwright
  test "a disconnected nested channel is not ready even with a connected CSS marker" do
    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url(), timeout: 1_000)
      |> visit("/live/nested")

    Playwright.evaluate(
      session,
      """
      async () => {
        const element = document.getElementById('nested-child')
        const view = window.liveSocket.getViewByEl(element)
        await new Promise(resolve => view.channel.leave().receive('ok', resolve))
        element.classList.add('phx-connected')
      }
      """,
      is_function: true
    )

    assert_raise RuntimeError, ~r/expected every LiveView root to be connected/, fn ->
      visit(session, "/live/nested#disconnected-child")
    end
  end

  @tag driver: :playwright
  test "names the destination, page, frame, and expected marker on a readiness timeout" do
    session =
      start_session(:playwright,
        base_url: Fluffy.TestServer.base_url(),
        endpoint: Fluffy.TestWeb.Endpoint,
        timeout: 1_000
      )

    error =
      assert_raise RuntimeError, fn ->
        visit(session, "/actions/disconnected-live-root")
      end

    assert error.message =~ "/actions/disconnected-live-root"
    assert error.message =~ "page \""
    assert error.message =~ "frame \""
    assert error.message =~ "every LiveView root to be connected with its join complete"
  end
end
