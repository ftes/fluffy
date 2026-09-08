defmodule Fluffy.Conformance.PhoenixHTMLLinkActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.Page
  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "submits Phoenix.HTML's POST method override from a descendant click with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <a data-method="delete" data-to="delete?from=link#done" data-csrf="csrf-token">
                <span>Delete order</span>
              </a>
              """)
          },
          %{body: html("<h1>Deleted</h1>")}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
      |> click(by_text("Delete order", exact: true))
      |> expect(visible(by_role(:heading, name: "Deleted", exact: true)))
      |> expect(Page.to_have_url(TestHTTPFixtures.url(fixture, "/links/delete?from=link#done")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "POST"
      assert submission.path == "/links/delete"
      assert submission.query == "from=link"
      assert submission.body == "_csrf_token=csrf-token&_method=delete"
    end

    @tag driver: driver
    test "uses the nearest nested Phoenix.HTML action and supports buttons with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <div data-method="delete" data-to="outer" data-csrf="outer-csrf">
                <button data-method="patch" data-to="inner" data-csrf="inner-csrf">
                  <span id="nested-action-target">Use nearest action</span>
                </button>
              </div>
              """)
          },
          %{body: html("<h1>Inner action</h1>")}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
      |> click(by_css("#nested-action-target"))
      |> expect(visible(by_role(:heading, name: "Inner action", exact: true)))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "POST"
      assert submission.path == "/links/inner"
      assert submission.body == "_csrf_token=inner-csrf&_method=patch"
    end

    @tag driver: driver
    test "uses the stock Phoenix.HTML GET form shape with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <a data-method="get" data-to="search?discard=this" data-csrf="csrf-token">Search</a>
              """)
          },
          %{body: html("<h1>Results</h1>")}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
      |> click(by_text("Search", exact: true))
      |> expect(visible(by_role(:heading, name: "Results", exact: true)))
      |> expect(Page.to_have_url(TestHTTPFixtures.url(fixture, "/links/search?_csrf_token=csrf-token&_method=get")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "GET"
      assert submission.path == "/links/search"
      assert submission.query == "_csrf_token=csrf-token&_method=get"
      assert submission.body == ""
    end

    @tag driver: driver
    test "uses an empty hidden CSRF value when data-csrf is absent with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{body: html(~s(<a data-method="patch" data-to="update">Update</a>))},
          %{body: html("<h1>Updated</h1>")}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
      |> click(by_text("Update", exact: true))
      |> expect(visible(by_role(:heading, name: "Updated", exact: true)))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "POST"
      assert submission.body == "_csrf_token=&_method=patch"
    end

    @tag driver: driver
    test "follows redirects through ordinary navigation with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(fn request ->
          case request.path do
            "/links/start" ->
              %{body: html(~s(<a data-method="delete" data-to="delete">Delete</a>))}

            "/links/delete" ->
              %{status: 302, headers: [{"location", "done"}]}

            "/links/done" ->
              %{body: html("<h1>Redirect complete</h1>")}
          end
        end)

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
      |> click(by_text("Delete", exact: true))
      |> expect(visible(by_role(:heading, name: "Redirect complete", exact: true)))

      [_source, submission, redirected] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "POST"
      assert redirected.method == "GET"
      assert redirected.path == "/links/done"
    end
  end

  @tag driver: :playwright
  test "captures a Phoenix.HTML target=_blank form page with Playwright" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{
          body: html(~s(<h1>Opener</h1><a target="_blank" data-method="delete" data-to="delete">Delete</a>))
        },
        %{body: html("<h1>Deleted in popup</h1>")}
      ])

    opener_url = TestHTTPFixtures.url(fixture, "/links/start")

    :playwright
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
    |> wait_for(Event.popup(:deletion), &click(&1, by_text("Delete", exact: true)))
    |> expect(Page.to_have_url(opener_url))
    |> switch_page(:deletion)
    |> expect(visible(by_role(:heading, name: "Deleted in popup", exact: true)))

    [_source, submission] = TestHTTPFixtures.requests(fixture)
    assert submission.method == "POST"
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "submits the plain-link Phoenix.HTML action from a LiveView with #{driver}", %{
      driver: driver
    } do
      fixture = TestHTTPFixtures.register(%{body: html("<h1>Deleted from LiveView</h1>")})
      action = TestHTTPFixtures.path(fixture, "/live-delete")

      driver
      |> start_test_session()
      |> visit("/live/phoenix-html-link?action=#{URI.encode_www_form(action)}")
      |> click(by_text("Delete from LiveView", exact: true))
      |> expect(visible(by_role(:heading, name: "Deleted from LiveView", exact: true)))

      [submission] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "POST"
      assert submission.path == "/live-delete"
      assert submission.body == "_csrf_token=live-csrf&_method=delete"
    end
  end

  test "Live rejects a competing action on a Phoenix.HTML ancestor clicked through a descendant" do
    fixture = TestHTTPFixtures.register(%{body: html("<h1>Unexpected submission</h1>")})
    action = TestHTTPFixtures.path(fixture, "/live-delete")

    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/phoenix-html-link?action=#{URI.encode_www_form(action)}&competing_action=true")

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        click(session, by_css("#live-delete-label"))
      end

    assert error.capability == :phoenix_html_live_action_conflict
    assert TestHTTPFixtures.requests(fixture) == []
  end

  test "Playwright observes and accepts Phoenix.HTML's multiline confirmation" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{
          body:
            html("""
            <h1>Before confirmation</h1>
            <a data-method="delete" data-to="delete" data-confirm="Delete?&#10;This cannot be undone.">
              Delete with confirmation
            </a>
            """)
        },
        %{body: html("<h1>Deleted after confirmation</h1>")}
      ])

    :playwright
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
    |> wait_for(
      Event.dialog(:confirmation, accept: true),
      &click(&1, by_text("Delete with confirmation", exact: true))
    )
    |> expect(dialog_message(:confirmation, "Delete?\nThis cannot be undone."))
    |> expect(visible(by_role(:heading, name: "Deleted after confirmation", exact: true)))

    assert [_source, submission] = TestHTTPFixtures.requests(fixture)
    assert submission.path == "/links/delete"
  end

  test "Playwright cancellation prevents Phoenix.HTML's confirmed action" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{
          body:
            html("""
            <h1>Before confirmation</h1>
            <a data-method="delete" data-to="delete" data-confirm="Proceed?">
              Delete with confirmation
            </a>
            """)
        },
        %{body: html("<h1>Unexpected submission</h1>")}
      ])

    source_url = TestHTTPFixtures.url(fixture, "/links/start")

    :playwright
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
    |> wait_for(
      Event.dialog(:confirmation, dismiss: true),
      &click(&1, by_text("Delete with confirmation", exact: true))
    )
    |> expect(dialog_action(:confirmation, :dismiss))
    |> expect(Page.to_have_url(source_url))
    |> expect(visible(by_role(:heading, name: "Before confirmation", exact: true)))

    assert [_source] = TestHTTPFixtures.requests(fixture)
  end

  test "Phoenix ignores data-confirm and performs the structural Phoenix.HTML action" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{
          body:
            html("""
            <a data-method="delete" data-to="delete" data-confirm="Proceed?">
              Delete without a browser
            </a>
            """)
        },
        %{body: html("<h1>Deleted structurally</h1>")}
      ])

    :phoenix
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
    |> click(by_text("Delete without a browser", exact: true))
    |> expect(visible(by_role(:heading, name: "Deleted structurally", exact: true)))

    assert [_source, submission] = TestHTTPFixtures.requests(fixture)
    assert submission.path == "/links/delete"
  end

  test "a partial Phoenix.HTML attribute pair preserves ordinary anchor navigation" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{body: html(~s(<a href="next" data-method="delete">Next</a>))},
        %{body: html("<h1>Next</h1>")}
      ])

    :phoenix
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/links/start"))
    |> click(by_role(:link, name: "Next", exact: true))
    |> expect(visible(by_role(:heading, name: "Next", exact: true)))

    [_source, navigation] = TestHTTPFixtures.requests(fixture)
    assert navigation.method == "GET"
    assert navigation.path == "/links/next"
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body) do
    """
    <!doctype html>
    <html>
      <head><script type="module" src="/assets/test_browser.js"></script></head>
      <body><main>#{body}</main></body>
    </html>
    """
  end
end
