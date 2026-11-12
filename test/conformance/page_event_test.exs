defmodule Fluffy.Conformance.PageEventTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.Page
  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server

  @tag driver: :playwright
  test "page/2 turns a PlaywrightEx page of the session into its handle, and rejects another context's" do
    session = session_for_html(:playwright, "<h1>Main</h1>")
    other = new_page(session)
    native = unwrap_and_return(switch_page(session, other), & &1)
    assert page(session, native) == other
    assert session |> switch_page(page(session, native)) |> current_page() == other

    elsewhere = session_for_html(:playwright, "<h1>Elsewhere</h1>")
    native = unwrap_and_return(elsewhere, & &1)
    assert_raise ArgumentError, ~r/another browser context/, fn -> page(session, native) end
  end

  for event_type <- [:page, :popup] do
    @tag driver: :playwright
    test "#{event_type} remains bound to its registration source after switching pages" do
      {session, fixture} = browser_session()
      other_wait = wait_for(session, Event.popup())
      click(session, by_role(:link, name: "Other", exact: true))
      other = await(other_wait)
      pending = wait_for(session, apply(Event, unquote(event_type), []))
      session |> switch_page(other) |> click(by_role(:link, name: "Unrelated", exact: true))
      await_pages(session, &(length(&1) >= 3))
      click(session, by_role(:link, name: "Details", exact: true))
      captured = await(pending)

      {path, opener} =
        case unquote(event_type) do
          :page -> {"/unrelated", other}
          :popup -> {"/details", current_page(session)}
        end

      assert Page.opener(captured) == opener
      session |> switch_page(captured) |> expect(page_to_have_url(HTTPFixtures.url(fixture, path)))
    end
  end

  @tag driver: :playwright
  test "page and popup waits identify the same physical page and preserve the opener selection" do
    {session, fixture} = browser_session()
    page_wait = wait_for(session, Event.page())
    popup_wait = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Details", exact: true))
    page = await(page_wait)
    assert await(popup_wait) == page
    assert Page.opener(page) == current_page(session)
    assert page in pages(session)

    session
    |> switch_page(page)
    |> expect(:heading |> by_role(name: "Details") |> to_be_visible())
    |> expect(page_to_have_url(HTTPFixtures.url(fixture, "/details")))
    |> close_page()
    |> switch_page(current_page(session))
    |> expect(page_to_have_url(HTTPFixtures.url(fixture, "/start")))

    assert pages(session) == [current_page(session)]
  end

  # Holding the session runtime while the popup opens and closes keeps Fluffy
  # from registering the popup, as when it closes before Fluffy sees it.
  @tag driver: :playwright
  test "page and popup waits resolve with a popup that closed before Fluffy saw it" do
    {session, _fixture} = browser_session()
    page_wait = wait_for(session, Event.page())
    popup_wait = wait_for(session, Event.popup())
    frame = Fluffy.Session.page_state(session).frame
    owner = self()

    holder =
      Task.async(fn ->
        Fluffy.SessionRuntime.run(session.runtime, fn ->
          send(owner, :held)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :held

    assert {:ok, nil} =
             PlaywrightEx.Frame.evaluate(frame, """
             async () => {
               const popup = window.open('details')
               popup.close()
               while (!popup.closed) await new Promise(resolve => setTimeout(resolve, 20))
             }
             """)

    send(session.runtime, :release)
    Task.await(holder)
    popup = await(popup_wait)
    assert await(page_wait) == popup
    # The opener can see a popup closed before the driver reports it.
    await_pages(session, &(popup not in &1))
    assert_raise ArgumentError, ~r/is closed/, fn -> Page.url(popup) end
  end

  @tag driver: :playwright
  test "a scoped page expectation ignores callback page selection and return values" do
    {session, _fixture} = browser_session()
    other = switch_page(session, new_page(session))

    assert expect_event(
             session,
             Event.page(),
             fn original ->
               new_page(original)
               other
             end,
             fn page ->
               assert Page.opener(page) == nil
               :ignored
             end
           ) == session

    assert length(pages(session)) == 3
    refute current_page(session) == current_page(other)
  end

  @tag driver: :playwright
  test "a settled popup stays available when the action outlives the wait deadline" do
    {session, fixture} = browser_session()

    # The deadline leaves room for a browser click under parallel cases
    # (Firefox dispatches input for one page at a time); the action still
    # outlives it.
    expect_event(
      session,
      Event.popup(),
      fn input ->
        click(input, by_role(:link, name: "Redirect", exact: true))
        Process.sleep(3_000)
      end,
      fn page ->
        session |> switch_page(page) |> expect(page_to_have_url(HTTPFixtures.url(fixture, "/details")))
      end,
      timeout: 3_000
    )
  end

  @tag driver: :playwright
  test "formtarget opens a page while preserving its submitter" do
    {session, fixture} = browser_session()
    pending = wait_for(session, Event.popup())
    click(session, by_role(:button, name: "Buy now"))
    session |> switch_page(await(pending)) |> expect(:heading |> by_role(name: "Receipt") |> to_be_visible())
    submission = Enum.find(HTTPFixtures.requests(fixture), &(&1.path == "/receipt"))
    assert submission.method == "POST"
    assert submission.body == "item=book&commit=Buy"
    expect(session, page_to_have_url(HTTPFixtures.url(fixture, "/start")))
  end

  @tag driver: :playwright
  test "the first popup keeps its own final document when another page also loads" do
    {session, fixture} = browser_session()
    pending = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Redirect", exact: true))
    await_pages(session, &(length(&1) >= 2))
    click(session, by_role(:link, name: "Other", exact: true))

    session
    |> switch_page(await(pending))
    |> expect(page_to_have_url(HTTPFixtures.url(fixture, "/details")))
    |> expect(:heading |> by_role(name: "Details") |> to_be_visible())
  end

  for driver <- [:static, :live] do
    test "#{driver} rejects page events before invoking an action" do
      session =
        case unquote(driver) do
          :static -> session_for_html(:static, "<h1>Main</h1>")
          :live -> :phoenix |> start_session() |> visit("/live/chamber-map")
        end

      for event <- [Event.page(), Event.popup()] do
        error =
          assert_raise Fluffy.CapabilityError, fn ->
            expect_event(session, event, fn _ -> flunk("unsupported action ran") end)
          end

        assert error.capability == :pages
        assert error.driver == unquote(driver)
      end

      for operation <- [
            fn -> current_page(session) end,
            fn -> pages(session) end,
            fn -> switch_page(session, Fluffy.Session.handle(session)) end,
            fn -> close_page(session) end,
            fn -> close_page(session, Fluffy.Session.handle(session)) end,
            fn -> new_page(session) end
          ] do
        error = assert_raise Fluffy.CapabilityError, operation
        assert error.capability == :pages
        assert error.driver == unquote(driver)
      end
    end
  end

  @tag driver: :playwright
  test "popup waiting resolves before the new document finishes loading" do
    owner = self()

    fixture =
      HTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{body: ~s(<a href="slow" target="_blank">Open</a>)}

          "/slow" ->
            %{
              stream: fn conn ->
                {:ok, conn} =
                  Plug.Conn.chunk(conn, "<!doctype html><html><body><h1>Loading</h1>" <> HTTPFixtures.sniff_padding())

                send(owner, {:stream, self()})

                receive do
                  :finish -> :ok
                after
                  30_000 -> :ok
                end

                {:ok, conn} = Plug.Conn.chunk(conn, "<p>Loaded</p></body></html>")
                conn
              end
            }
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Server.base_url())
      |> visit(HTTPFixtures.path(fixture, "/start"))

    pending = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Open"))
    # WebKit requests the popup's document only after Playwright initialized the new page, so
    # wait as long as the popup wait itself may.
    assert_receive {:stream, server}, Fluffy.Session.timeout(session)

    try do
      page = await(pending)
      assert Page.url(page) == HTTPFixtures.url(fixture, "/slow")
      send(server, :finish)
      session |> switch_page(page) |> expect("Loaded" |> by_text() |> to_be_visible())
    after
      send(server, :finish)
    end
  end

  # A click returns before its popup exists and the popups of separate clicks
  # can appear in either order, so a test that relies on their order waits for
  # the first before the next click.
  defp await_pages(session, condition, attempts \\ 1_500) do
    pages = pages(session)

    cond do
      condition.(pages) ->
        :ok

      attempts == 0 ->
        flunk("the session's pages never met the condition: #{inspect(pages)}")

      true ->
        Process.sleep(10)
        await_pages(session, condition, attempts - 1)
    end
  end

  defp browser_session do
    fixture =
      HTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body: """
              <!doctype html><html><body><h1>Opener</h1>
              <a href="other" target="_blank">Other</a>
              <a href="details" target="_blank">Details</a>
              <a href="redirect" target="_blank">Redirect</a>
              <form method="post" action="receipt"><input name="item" value="book">
              <button formtarget="_blank" name="commit" value="Buy">Buy now</button></form>
              </body></html>
              """
            }

          "/other" ->
            %{body: ~s(<a href="unrelated" target="_blank">Unrelated</a>)}

          "/unrelated" ->
            %{body: "<h1>Unrelated</h1>"}

          "/details" ->
            %{body: "<h1>Details</h1>"}

          "/redirect" ->
            %{status: 302, headers: [{"location", "details"}], body: ""}

          "/receipt" ->
            %{body: "<h1>Receipt</h1>"}
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Server.base_url())
      |> visit(HTTPFixtures.path(fixture, "/start"))

    {session, fixture}
  end
end
