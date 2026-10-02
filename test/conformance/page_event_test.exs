defmodule Fluffy.Conformance.PageEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Page
  alias Fluffy.TestHTTPFixtures

  for event_type <- [:page, :popup] do
    @tag driver: :playwright
    test "#{event_type} remains bound to its registration source after switching pages" do
      {session, fixture} = browser_session()
      other_wait = wait_for(session, Event.popup())
      click(session, by_role(:link, name: "Other", exact: true))
      other = await(other_wait)
      pending = wait_for(session, apply(Event, unquote(event_type), []))
      session |> switch_page(other) |> click(by_role(:link, name: "Unrelated", exact: true))
      click(session, by_role(:link, name: "Details", exact: true))
      captured = await(pending)

      {path, opener} =
        case unquote(event_type) do
          :page -> {"/unrelated", other}
          :popup -> {"/details", current_page(session)}
        end

      assert Page.opener(captured) == opener
      session |> switch_page(captured) |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, path)))
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
    |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/details")))
    |> expect(page_to_have_status(202))
    |> close_page()
    |> switch_page(current_page(session))
    |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/start")))

    assert pages(session) == [current_page(session)]
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

    expect_event(
      session,
      Event.popup(),
      fn input ->
        click(input, by_role(:link, name: "Redirect", exact: true))
        Process.sleep(1_000)
      end,
      fn page ->
        session |> switch_page(page) |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/details")))
      end,
      timeout: 1_000
    )
  end

  @tag driver: :playwright
  test "formtarget opens a page while preserving its submitter" do
    {session, fixture} = browser_session()
    pending = wait_for(session, Event.popup())
    click(session, by_role(:button, name: "Buy now"))
    session |> switch_page(await(pending)) |> expect(:heading |> by_role(name: "Receipt") |> to_be_visible())
    submission = Enum.find(TestHTTPFixtures.requests(fixture), &(&1.path == "/receipt"))
    assert submission.method == "POST"
    assert submission.body == "item=book&commit=Buy"
    expect(session, page_to_have_url(TestHTTPFixtures.url(fixture, "/start")))
  end

  @tag driver: :playwright
  test "the first popup retains its own final response when another page also loads" do
    {session, fixture} = browser_session()
    pending = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Redirect", exact: true))
    click(session, by_role(:link, name: "Other", exact: true))

    session
    |> switch_page(await(pending))
    |> expect(page_to_have_url(TestHTTPFixtures.url(fixture, "/details")))
    |> expect(page_to_have_status(202))
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

      assert switch_page(session, current_page(session)) == session
      error = assert_raise Fluffy.CapabilityError, fn -> close_page(session) end
      assert error.capability == :pages
    end
  end

  @tag driver: :playwright
  test "popup waiting resolves before the new document finishes loading" do
    owner = self()

    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{body: ~s(<a href="slow" target="_blank">Open</a>)}

          "/slow" ->
            %{
              stream: fn conn ->
                {:ok, conn} = Plug.Conn.chunk(conn, "<!doctype html><html><body><h1>Loading</h1>")
                send(owner, {:stream, self()})

                receive do
                  :finish -> :ok
                after
                  5_000 -> :ok
                end

                {:ok, conn} = Plug.Conn.chunk(conn, "<p>Loaded</p></body></html>")
                conn
              end
            }
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))

    pending = wait_for(session, Event.popup())
    click(session, by_role(:link, name: "Open"))
    assert_receive {:stream, server}

    try do
      page = await(pending)
      assert Page.url(page) == TestHTTPFixtures.url(fixture, "/slow")
      send(server, :finish)
      session |> switch_page(page) |> expect("Loaded" |> by_text() |> to_be_visible())
    after
      send(server, :finish)
    end
  end

  defp browser_session do
    fixture =
      TestHTTPFixtures.register(fn request ->
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
            %{status: 202, body: "<h1>Details</h1>"}

          "/redirect" ->
            %{status: 302, headers: [{"location", "details"}], body: ""}

          "/receipt" ->
            %{body: "<h1>Receipt</h1>"}
        end
      end)

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit(TestHTTPFixtures.path(fixture, "/start"))

    {session, fixture}
  end
end
