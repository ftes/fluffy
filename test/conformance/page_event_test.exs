defmodule Fluffy.Conformance.PageEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Page
  alias Fluffy.TestHTTPFixtures

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
      |> expect(visible(by_text("Details page")))
      |> expect(Page.to_have_url(details_url))
      |> expect(Page.to_have_status(202))
      |> expect(Page.to_have_opener(:main))
      |> close_page()

    assert page_names(session) == [:main]

    session
    |> expect(visible(by_text("Opener")))
    |> expect(Page.to_have_url(opener_url))
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
      |> expect(visible(by_text("Opener")))
      |> expect(Page.to_have_url(opener_url))
      |> switch_page(:receipt)
      |> expect(visible(by_text("Receipt page")))
      |> expect(Page.to_have_url(receipt_url))

    [_source, submission] = TestHTTPFixtures.requests(fixture)
    assert submission.method == "POST"
    assert submission.body == "item=book&commit=Buy"

    session
    |> close_page()
    |> expect(Page.to_have_url(opener_url))
  end

  for driver <- [:static, :live] do
    test "#{driver} rejects popup capture before running the action and rejects page lifecycle operations" do
      session =
        case unquote(driver) do
          :static -> Fluffy.session_for_html(:static, "<h1>Main</h1>")
          :live -> :phoenix |> start_test_session() |> visit("/live/chamber-map")
        end

      error =
        assert_raise Fluffy.CapabilityError, fn ->
          wait_for(session, Event.popup(:child), fn _session ->
            flunk("unsupported popup capture must not run the action")
          end)
        end

      assert error.capability == :pages
      assert error.driver == unquote(driver)

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
end
