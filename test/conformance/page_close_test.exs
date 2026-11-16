defmodule Fluffy.Conformance.PageCloseTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.Support.HTTPFixtures

  # Like Playwright: Firefox fails such a click, which Playwright leaves as a known Firefox bug.
  @tag driver: :playwright
  test "an action that closes its own page succeeds, except on Firefox, and leaves the opener usable" do
    {session, popup} = popup_session()
    main = current_page(session)
    authorize = fn -> click(popup, by_role(:button, name: "Sign permission slip")) end

    if playwright_engine?(:firefox),
      do: assert_raise(Fluffy.OperationError, ~r/closed/, authorize),
      else: assert(authorize.() == popup)

    session
    |> switch_page(main)
    |> expect("done" |> by_text(exact: true) |> to_be_visible())
  end

  @tag driver: :playwright
  test "the next action on a page its own action closed reports the closed page" do
    {_session, popup} = popup_session(:after_click)
    pending = wait_for(popup, Event.close())
    click(popup, by_role(:button, name: "Sign permission slip"))
    await(pending)

    assert_raise ArgumentError, ~r/page #Reference<.*> is closed/, fn ->
      click(popup, by_role(:button, name: "Sign permission slip"))
    end
  end

  @tag driver: :playwright
  test "a close expectation resolves with the closed page" do
    {session, popup} = popup_session(:after_click)
    closed = current_page(popup)

    expect_event(popup, Event.close(), &click(&1, by_role(:button, name: "Sign permission slip")), fn page ->
      assert page == closed
    end)

    refute closed in pages(session)
  end

  @tag driver: :playwright
  test "close_page/2 settles close waits and runs close listeners" do
    {session, popup} = popup_session()
    closed = current_page(popup)
    owner = self()
    pending = wait_for(popup, Event.close())
    once(popup, Event.close(), &send(owner, {:closed, &1}))
    close_page(session, closed)

    assert await(pending) == closed
    assert_receive {:closed, ^closed}
  end

  test "reports close events as browser-only before invoking an action" do
    session = session_for_html(:static, "<h1>Main</h1>")

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        expect_event(session, Event.close(), fn _ -> flunk("unsupported action ran") end)
      end

    assert error.capability == :pages
  end

  # `:after_click` closes once the click has returned, which every browser allows.
  defp popup_session(close \\ :in_click) do
    close_script = if close == :after_click, do: "setTimeout(() => window.close())", else: "window.close()"

    fixture =
      HTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body: """
              <!doctype html><html><body><a href="popup" target="_blank" rel="opener">Open</a><p id="message"></p>
              <script>addEventListener('message', event => { message.textContent = event.data })</script>
              </body></html>
              """
            }

          "/popup" ->
            %{
              body: """
              <!doctype html><html><body>
              <button onclick="window.opener.postMessage('done', '*'); #{close_script}">Sign permission slip</button>
              </body></html>
              """
            }
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.Support.Server.base_url())
      |> visit(HTTPFixtures.path(fixture, "/start"))

    pending = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Open"))
    {session, switch_page(session, await(pending))}
  end
end
