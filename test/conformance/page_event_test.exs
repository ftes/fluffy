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
    test "#{event_type} capture respects its scope and records the actual opener" do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/start" ->
              %{
                body:
                  html(
                    ~s(<a href="other" target="_blank">Open other</a><a href="selected" target="_blank">Open selected</a>)
                  )
              }

            "/other" ->
              %{body: html(~s(<a href="unrelated" target="_blank">Open unrelated</a>))}

            "/unrelated" ->
              %{body: html("<h1>Unrelated</h1>")}

            "/selected" ->
              %{body: html("<h1>Selected</h1>")}
          end
        end)

      session =
        :playwright
        |> start_test_session()
        |> visit(TestHTTPFixtures.path(fixture, "/start"))
        |> wait_for(Event.popup(:other), &click(&1, by_role(:link, name: "Open other")))

      event = apply(Event, unquote(event_type), [:captured])

      session =
        wait_for(session, event, fn session ->
          session
          |> switch_page(:other)
          |> click(by_role(:link, name: "Open unrelated"))
          |> switch_page(:main)
          |> click(by_role(:link, name: "Open selected"))
          |> switch_page(:other)
        end)

      {path, opener} =
        case unquote(event_type) do
          :page -> {"/unrelated", :other}
          :popup -> {"/selected", :main}
        end

      assert Page.url(page(session, :captured)) == TestHTTPFixtures.url(fixture, path)
      assert Page.opener(page(session, :captured)) == opener
    end
  end

  @tag driver: :playwright
  test "captures, names, switches, and closes a declarative new page with Playwright" do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body: html(~s(<h1>Opener</h1><a href="details" target="_blank">Open details</a>))
            }

          "/details" ->
            %{status: 202, body: html("<h1>Details page</h1>")}
        end
      end)

    opener_url = TestHTTPFixtures.url(fixture, "/start")
    details_url = TestHTTPFixtures.url(fixture, "/details")
    session = start_test_session(:playwright)

    session =
      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.popup(:details), &click(&1, by_role(:link, name: "Open details")))

    captured_page = page(session, :details)
    assert Page.name(captured_page) == :details
    assert Page.url(captured_page) == details_url
    assert Page.status(captured_page) == 202
    assert Page.opener(captured_page) == :main
    assert Page.revision(captured_page) == 1

    assert Enum.sort(page_names(session)) == [:details, :main]

    session =
      session
      |> switch_page(:details)
      |> expect("Details page" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(details_url))
      |> expect(Fluffy.Expect.page_to_have_status(202))
      |> expect(Fluffy.Expect.page_to_have_opener(:main))
      |> close_page()

    assert page_names(session) == [:main]

    session
    |> expect("Opener" |> by_text() |> to_be_visible())
    |> expect(Fluffy.Expect.page_to_have_url(opener_url))
  end

  @tag driver: :playwright
  test "initializes a captured popup after the action outlives the capture deadline" do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" -> %{body: html(~s(<a href="redirect" target="_blank">Open details</a>))}
          "/redirect" -> %{status: 302, headers: [{"location", "details"}], body: ""}
          "/details" -> %{status: 202, body: html("<h1>Details page</h1>")}
        end
      end)

    session =
      :playwright
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.popup(:details, timeout: 1_000), fn session ->
        session = click(session, by_role(:link, name: "Open details"))
        Process.sleep(1_000)
        session
      end)

    assert Page.url(page(session, :details)) == TestHTTPFixtures.url(fixture, "/details")
    assert Page.status(page(session, :details)) == 202
    assert Page.opener(page(session, :details)) == :main
    session |> switch_page(:details) |> expect("Details page" |> by_text() |> to_be_visible())
  end

  @tag driver: :playwright
  test "captures a formtarget new page and preserves its submitter with Playwright" do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body:
                html("""
                <h1>Opener</h1>
                <form method="post" action="receipt">
                  <input name="item" value="book">
                  <button formtarget="_blank" name="commit" value="Buy">Buy now</button>
                </form>
                """)
            }

          "/receipt" ->
            %{body: html("<h1>Receipt page</h1>")}
        end
      end)

    opener_url = TestHTTPFixtures.url(fixture, "/start")
    receipt_url = TestHTTPFixtures.url(fixture, "/receipt")
    session = start_test_session(:playwright)

    session =
      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.popup(:receipt), &click(&1, by_role(:button, name: "Buy now")))
      |> expect("Opener" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(opener_url))
      |> switch_page(:receipt)
      |> expect("Receipt page" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(receipt_url))

    [_source, submission] = TestHTTPFixtures.requests(fixture)
    assert submission.method == "POST"
    assert submission.body == "item=book&commit=Buy"

    session
    |> close_page()
    |> expect(Fluffy.Expect.page_to_have_url(opener_url))
  end

  for driver <- [:static, :live] do
    test "#{driver} rejects popup capture before running the action and rejects page lifecycle operations" do
      session =
        case unquote(driver) do
          :static -> Fluffy.session_for_html(:static, "<h1>Main</h1>")
          :live -> :phoenix |> start_test_session() |> visit("/live/chamber-map")
        end

      for event <- [Event.page(:child), Event.popup(:child)] do
        error =
          assert_raise Fluffy.CapabilityError, fn ->
            wait_for(session, event, fn _session ->
              flunk("unsupported page capture must not run the action")
            end)
          end

        assert error.capability == :pages
        assert error.driver == unquote(driver)
      end

      for action <- [&switch_page(&1, :main), &close_page/1] do
        error = assert_raise Fluffy.CapabilityError, fn -> action.(session) end
        assert error.capability == :pages
      end
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"

  @tag driver: :playwright
  test "associates the first popup with its final redirect response when another page also loads" do
    fixture =
      TestHTTPFixtures.register(fn request ->
        case request.path do
          "/start" ->
            %{
              body:
                html(
                  ~s(<a href="redirect" target="_blank">First popup</a><a href="other" target="_blank">Other popup</a>)
                )
            }

          "/redirect" ->
            %{status: 302, headers: [{"location", "final"}], body: ""}

          "/final" ->
            %{status: 203, body: html("<script>history.replaceState({}, '', 'patched')</script><h1>Selected popup</h1>")}

          "/other" ->
            %{status: 202, body: html("<h1>Other popup</h1>")}
        end
      end)

    session =
      :playwright
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> wait_for(Event.popup(:selected), fn session ->
        session
        |> click(by_role(:link, name: "First popup"))
        |> click(by_role(:link, name: "Other popup"))
      end)

    assert Page.url(page(session, :selected)) == TestHTTPFixtures.url(fixture, "/patched")
    assert Page.status(page(session, :selected)) == 203
    session |> switch_page(:selected) |> expect("Selected popup" |> by_text() |> to_be_visible())
  end
end
