defmodule Fluffy.Conformance.ImplicitSubmissionTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Page
  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "Enter submits through the default submitter with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit">
                <label>Name <input name="name"></label>
                <button name="commit" value="first">First</button>
                <button name="commit" value="second">Second</button>
              </form>
              """)
          },
          %{status: 201, body: html("<h1>Submitted</h1>")}
        ])

      session = start_test_session(driver)

      destination = TestHTTPFixtures.url(fixture, "/submit")

      session =
        session
        |> visit(TestHTTPFixtures.path(fixture, "/start"))
        |> fill(by_label("Name"), "Ada")
        |> press(by_label("Name"), "Enter")
        |> expect("Submitted" |> by_text() |> to_be_visible())
        |> expect(Page.to_have_status(201))

      assert Fluffy.Session.current_page(session).url == destination

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.method == "POST"
      assert submission.path == "/submit"
      assert submission.body == "name=Ada&commit=first"
    end

    @tag driver: driver
    test "Enter treats an invalid input type as the text state with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit">
                <label>Name <input type="invented" name="name" value="Ada"></label>
              </form>
              """)
          },
          %{body: html("<h1>Submitted invalid type</h1>")}
        ])

      driver
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> press(by_label("Name"), "Enter")
      |> expect("Submitted invalid type" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body == "name=Ada"
    end

    @tag driver: driver
    test "Enter takes the LiveView form's default submit path with #{driver}", %{driver: driver} do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("First"), "Ada")
      |> press(by_label("First"), "Enter")
      |> expect("Saved commit: save" |> by_text() |> to_be_visible())
      |> expect("Last first: Ada" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "Enter submits after a blur-debounced Live mutation with #{driver}", %{driver: driver} do
      session = start_test_session(driver)

      session
      |> visit("/live/potions")
      |> fill(by_label("Debounced", exact: true), "before Enter")
      |> press(by_label("First"), "Enter")
      |> expect("Last debounced: before Enter" |> by_text() |> to_be_visible())
      |> expect("Event targets: profile/debounced" |> by_text() |> to_be_visible())
      |> expect("Saved commit: save" |> by_text() |> to_be_visible())
    end

    @tag driver: driver
    test "Enter submits one blocking control without a submitter with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit">
                <label>Name <input name="name"></label>
              </form>
              """)
          },
          %{body: html("<h1>Submitted</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> fill(by_label("Name"), "Ada")
      |> press(by_label("Name"), "Enter")
      |> expect("Submitted" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body == "name=Ada"
    end

    @tag driver: driver
    test "a disabled default submitter suppresses Enter submission with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register(%{
          body:
            html("""
            <form method="post" action="submit">
              <label>Name <input name="name"></label>
              <button disabled>Disabled default</button>
              <button>Later enabled submitter</button>
            </form>
            <p>Still here</p>
            """)
        })

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> press(by_label("Name"), "Enter")
      |> expect("Still here" |> by_text() |> to_be_visible())

      assert [_source] = TestHTTPFixtures.requests(fixture)
    end

    @tag driver: driver
    test "an external submitter is the default when first in tree order with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <button form="search" name="commit" value="external">External</button>
              <form id="search" method="post" action="submit">
                <label>Name <input name="name"></label>
                <button name="commit" value="inside">Inside</button>
              </form>
              """)
          },
          %{body: html("<h1>Submitted</h1>")}
        ])

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> fill(by_label("Name"), "Ada")
      |> press(by_label("Name"), "Enter")
      |> expect("Submitted" |> by_text() |> to_be_visible())

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body == "commit=external&name=Ada"
    end

    @tag driver: driver
    test "Enter is inert with multiple blocking controls and no submitter with #{driver}", %{
      driver: driver
    } do
      fixture =
        TestHTTPFixtures.register(%{
          body:
            html("""
            <form method="post" action="submit">
              <label>First <input name="first"></label>
              <label>Second <input name="second"></label>
            </form>
            <p>Still here</p>
            """)
        })

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> press(by_label("First"), "Enter")
      |> expect("Still here" |> by_text() |> to_be_visible())

      assert [_source] = TestHTTPFixtures.requests(fixture)
    end

    @tag driver: driver
    test "Enter in a textarea is inert with #{driver}", %{driver: driver} do
      fixture =
        TestHTTPFixtures.register(%{
          body:
            html("""
            <form method="post" action="submit">
              <label>Notes <textarea name="notes"></textarea></label>
              <button>Submit</button>
            </form>
            <p>Still here</p>
            """)
        })

      session = start_test_session(driver)

      session
      |> visit(TestHTTPFixtures.path(fixture, "/start"))
      |> press(by_label("Notes"), "Enter")
      |> expect("Still here" |> by_text() |> to_be_visible())

      assert [_source] = TestHTTPFixtures.requests(fixture)
    end
  end

  @tag driver: :playwright
  test "the browser submits a single text control without a submitter" do
    with_html(
      """
      <form onsubmit="event.preventDefault(); result.value = event.submitter ? event.submitter.value : 'none'">
        <label>Name <input name="name"></label>
      </form>
      <input id="result" aria-label="Result" value="waiting">
      """,
      fn session ->
        session
        |> press(by_label("Name"), "Enter")
        |> expect("Result" |> by_label() |> to_have_value("none"))
      end
    )
  end

  @tag driver: :playwright
  test "the browser uses the first associated submitter in tree order" do
    with_html(
      """
      <form onsubmit="event.preventDefault(); result.value = event.submitter ? event.submitter.value : 'none'">
        <label>Name <input name="name"></label>
        <button name="commit" value="first">First</button>
        <button name="commit" value="second">Second</button>
      </form>
      <input id="result" aria-label="Result" value="waiting">
      """,
      fn session ->
        session
        |> press(by_label("Name"), "Enter")
        |> expect("Result" |> by_label() |> to_have_value("first"))
      end
    )
  end

  @tag driver: :playwright
  test "a disabled default submitter suppresses implicit submission" do
    with_html(
      """
      <form onsubmit="event.preventDefault(); result.value = 'submitted'">
        <label>Name <input name="name"></label>
        <button disabled>Disabled default</button>
        <button>Later enabled submitter</button>
      </form>
      <input id="result" aria-label="Result" value="waiting">
      """,
      fn session ->
        session
        |> press(by_label("Name"), "Enter")
        |> expect("Result" |> by_label() |> to_have_value("waiting"))
      end
    )
  end

  @tag driver: :playwright
  test "an external submitter participates in default-submitter tree order" do
    with_html(
      """
      <button form="search" value="external">External</button>
      <form id="search" onsubmit="event.preventDefault(); result.value = event.submitter ? event.submitter.value : 'none'">
        <label>Name <input name="name"></label>
        <button value="inside">Inside</button>
      </form>
      <input id="result" aria-label="Result" value="waiting">
      """,
      fn session ->
        session
        |> press(by_label("Name"), "Enter")
        |> expect("Result" |> by_label() |> to_have_value("external"))
      end
    )
  end

  @tag driver: :playwright
  test "a form without a submitter needs exactly one blocking text control" do
    with_html(
      """
      <form onsubmit="event.preventDefault(); result.value = 'submitted'">
        <label>First <input name="first"></label>
        <label>Second <input name="second"></label>
      </form>
      <input id="result" aria-label="Result" value="waiting">
      """,
      fn session ->
        session
        |> press(by_label("First"), "Enter")
        |> expect("Result" |> by_label() |> to_have_value("waiting"))
      end
    )
  end

  @tag driver: :playwright
  test "Enter in a textarea does not implicitly submit" do
    with_html(
      """
      <form onsubmit="event.preventDefault(); result.value = 'submitted'">
        <label>Notes <textarea name="notes"></textarea></label>
        <button>Submit</button>
      </form>
      <input id="result" aria-label="Result" value="waiting">
      """,
      fn session ->
        session
        |> press(by_label("Notes"), "Enter")
        |> expect("Result" |> by_label() |> to_have_value("waiting"))
      end
    )
  end

  @tag driver: :playwright
  test "constraint validation prevents implicit submission" do
    with_html(
      """
      <form onsubmit="event.preventDefault(); result.value = 'submitted'">
        <label>Name <input name="name" required></label>
        <button>Submit</button>
      </form>
      <input id="result" aria-label="Result" value="waiting">
      """,
      fn session ->
        session
        |> press(by_label("Name"), "Enter")
        |> expect("Result" |> by_label() |> to_have_value("waiting"))
      end
    )
  end

  @tag driver: :playwright
  test "a key handler that prevents default suppresses implicit submission" do
    with_html(
      """
      <form onsubmit="event.preventDefault(); result.value = 'submitted'">
        <label>Name <input name="name" onkeydown="event.preventDefault()"></label>
        <button>Submit</button>
      </form>
      <input id="result" aria-label="Result" value="waiting">
      """,
      fn session ->
        session
        |> press(by_label("Name"), "Enter")
        |> expect("Result" |> by_label() |> to_have_value("waiting"))
      end
    )
  end

  test "Static names inline key handlers as an Enter default-action boundary" do
    session =
      session_for_html(
        :static,
        ~S|<form><label>Name <input aria-label="Name" onkeydown="event.preventDefault()"></label><button>Submit</button></form>|
      )

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        press(session, by_label("Name"), "Enter")
      end

    assert error.driver == :static
    assert error.capability == :keyboard_default_action
  end

  test "Static bypasses native constraint validation for implicit Enter" do
    fixture =
      TestHTTPFixtures.register_sequence([
        %{
          body: html(~s(<form action="submitted"><input aria-label="Name" required><button>Submit</button></form>))
        },
        %{body: html("<h1>Submitted</h1>")}
      ])

    :phoenix
    |> start_test_session()
    |> visit(TestHTTPFixtures.path(fixture, "/start"))
    |> press(by_label("Name"), "Enter")
    |> expect("Submitted" |> by_text() |> to_be_visible())
  end

  defp with_html(html, fun) do
    session = session_for_html(:playwright, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp html(body), do: "<!doctype html><html><body><main>#{body}</main></body></html>"
end
