defmodule Fluffy.Conformance.FrameLocatorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.FrameLocator
  alias Fluffy.TestHTTPFixtures

  test "frame conversions and nested queries remain serializable locator values" do
    owner = "section" |> by_css() |> by_title("Checkout") |> nth(1)
    frame = content_frame(owner)
    assert FrameLocator.owner(frame) == owner
    assert inspect(frame) =~ "content_frame()"

    nested = frame |> frame_locator("#payment") |> by_role(:button, name: "Pay")
    assert %Fluffy.Locator{} = nested
    assert nested |> :erlang.term_to_binary() |> :erlang.binary_to_term() == nested

    assert Fluffy.Locator.Playwright.selector(nested) ==
             ~s(css=section >> internal:attr=[title="Checkout"i] >> nth=1 >> internal:control=enter-frame >> css=#payment >> internal:control=enter-frame >> internal:role=button[name="Pay"i])

    for locator <- [
          by_css(frame, "input"),
          by_role(frame, :textbox),
          by_text(frame, "Email"),
          by_label(frame, "Email"),
          by_placeholder(frame, "Email"),
          by_alt_text(frame, "Email"),
          by_title(frame, "Email"),
          by_test_id(frame, "email")
        ] do
      assert %Fluffy.Locator{} = locator
      assert Fluffy.Locator.crosses_frame?(locator)
    end
  end

  @tag driver: :playwright
  test "existing actions, assertions, and submit resolve inside nested frames" do
    form = """
    <form onsubmit="event.preventDefault(); document.querySelector('#status').textContent = 'Submitted'">
      <label>Email<input name="email"></label>
      <label><input type="checkbox">Updates</label>
      <input type="file" aria-label="Attachment">
      <select aria-label="Plan"><option value="basic">Basic</option><option value="pro">Pro</option></select>
      <button type="button" onclick="document.querySelector('#status').textContent = 'Clicked'">Save</button>
      <output id="status"></output>
    </form>
    """

    session = browser_html(iframe("outer", iframe("inner", form)))
    outer = frame_locator("#outer")
    inner = frame_locator(outer, "#inner")
    email = by_label(inner, "Email")
    status = by_css(inner, "#status")

    session
    |> expect(to_have_count(by_role(:textbox), 0))
    |> expect(to_have_count(FrameLocator.owner(outer), 1))
    |> fill(email, "buyer@example.com")
    |> expect(to_have_value(email, "buyer@example.com"))
    |> focus(email)
    |> press(email, "Tab")
    |> blur(email)
    |> expect(to_have_value(email, "buyer@example.com"))
    |> check(by_label(inner, "Updates"))
    |> expect(to_be_checked(by_label(inner, "Updates")))
    |> select_option(by_label(inner, "Plan"), "pro")
    |> expect(to_have_value(by_label(inner, "Plan"), "pro"))
    |> set_input_files(by_label(inner, "Attachment"), %Fluffy.FilePayload{name: "note.txt", bytes: "hello"})
    |> expect(to_have_value(by_label(inner, "Attachment"), "C:\\fakepath\\note.txt"))
    |> set_input_files(by_label(inner, "Attachment"), [])
    |> click(by_role(inner, :button, name: "Save"))
    |> expect(to_be_visible(by_text(status, "Clicked")))
    |> submit(by_css(inner, "form"))
    |> expect(to_be_visible(by_text(status, "Submitted")))
  end

  @tag driver: :playwright
  test "diagnostics resolve inside the frame and preserve the Playwright error" do
    session = browser_html(iframe("child", "<button disabled>Save</button><button>Other</button>"))
    frame = frame_locator("#child")

    error =
      assert_raise Fluffy.OperationError, fn ->
        click(session, by_role(frame, :button, name: "Save"), timeout: 50)
      end

    assert error.operation == :click
    assert %{error: %{name: "TimeoutError"}} = error.cause
    assert error.locator == by_role(frame, :button, name: "Save")
    assert error.message =~ "content_frame()"
    assert error.message =~ "playwright click"
    assert error.message =~ "Call log:"

    error =
      assert_raise ExUnit.AssertionError, fn ->
        expect(session, to_have_count(by_role(frame, :button), 1), timeout: 1_000)
      end

    assert error.message =~ "value: 2"
    assert error.message =~ "Call log:"
  end

  @tag driver: :playwright
  test "frame resolution failures keep the original Playwright diagnostic" do
    session = browser_html("<div id='not-a-frame'></div>")

    error =
      assert_raise Fluffy.OperationError, fn ->
        click(session, "#not-a-frame" |> frame_locator() |> by_role(:button), timeout: 1_000)
      end

    assert error.message =~ "content_frame()"
    assert error.message =~ "iframe"
    refute error.message =~ "Could not inspect"
  end

  @tag driver: :playwright
  test "LiveView inside a frame uses normal element actions without changing the active page" do
    session = browser_html(~s(<iframe id="live" src="/live/three-heads"></iframe>))
    page = Fluffy.Session.current_page(session)
    frame = frame_locator("#live")

    session =
      session
      |> expect(to_have_count(by_css(frame, "[data-phx-main].phx-connected"), 1))
      |> click(by_role(frame, :button, name: "Play the flute"))
      |> expect(to_be_visible(by_text(frame, "Sleeping heads: 1")))

    assert Fluffy.Session.current_page(session).id == page.id
    assert Fluffy.Session.current_page(session).url == page.url
  end

  @tag driver: :playwright
  test "child navigation leaves the page unchanged and top navigation updates it" do
    destination = TestHTTPFixtures.register(%{body: "<title>Destination</title><h1>Arrived</h1>"})
    url = TestHTTPFixtures.url(destination)
    child = TestHTTPFixtures.register(%{body: ~s(<a href="#{url}">Child</a><a href="#{url}" target="_top">Top</a>)})

    source =
      TestHTTPFixtures.register(%{
        body: ~s(<title>Parent</title><iframe id="child" src="#{TestHTTPFixtures.url(child)}"></iframe>)
      })

    source_url = TestHTTPFixtures.url(source)
    session = :playwright |> start_session(base_url: Fluffy.TestServer.base_url()) |> visit(source_url)
    frame = frame_locator("#child")

    session =
      session
      |> click(by_role(frame, :link, name: "Child"))
      |> expect(to_be_visible(by_role(frame, :heading, name: "Arrived")))

    session |> expect(page_to_have_url(source_url)) |> expect(page_to_have_title("Parent"))
    assert Fluffy.Session.current_page(session).url == source_url

    session = session |> reload() |> click(by_role(frame, :link, name: "Top")) |> expect(page_to_have_url(url))
    expect(session, page_to_have_title("Destination"))
    assert Fluffy.Session.current_page(session).url == url
  end

  @tag driver: :playwright
  test "actions and submission traverse a cross-origin frame" do
    child =
      TestHTTPFixtures.register(%{
        body: """
        <form onsubmit="event.preventDefault(); document.querySelector('output').textContent = 'Submitted'">
          <label>Email<input name="email"></label><output></output>
        </form>
        """
      })

    child_url = child |> TestHTTPFixtures.url() |> URI.parse() |> Map.put(:host, "localhost") |> URI.to_string()
    session = browser_html(~s(<iframe id="child" src="#{child_url}"></iframe>))
    frame = frame_locator("#child")
    email = by_label(frame, "Email")
    page = Fluffy.Session.current_page(session)

    session = session |> fill(email, "buyer@example.com") |> expect(to_have_value(email, "buyer@example.com"))
    assert Fluffy.Playwright.evaluate(session, "document.querySelector('iframe').contentDocument === null")
    session = session |> submit(by_css(frame, "form")) |> expect(to_be_visible(by_text(frame, "Submitted")))
    assert Fluffy.Session.current_page(session).id == page.id
    assert Fluffy.Session.current_page(session).url == page.url
  end

  @tag driver: :playwright
  test "a previously used locator resolves a replacement iframe" do
    session = browser_html(iframe("child", "<label>Email<input value='original'></label>"))
    email = "#child" |> frame_locator() |> by_label("Email")
    session = session |> fill(email, "before") |> expect(to_have_value(email, "before"))

    Fluffy.Playwright.evaluate(
      session,
      "html => { window.oldFrame = document.querySelector('#child'); window.oldFrame.outerHTML = html; }",
      is_function: true,
      arg: iframe("child", "<label>Email<input value='replacement'></label>")
    )

    assert Fluffy.Playwright.evaluate(session, "!window.oldFrame.isConnected")

    session
    |> expect(to_have_value(email, "replacement"))
    |> fill(email, "after")
    |> expect(to_have_value(email, "after"))
  end

  @tag driver: :playwright
  test "ambiguous frame owners fail strictly even when only one child matches" do
    session =
      browser_html(
        iframe("first", "<button onclick=\"this.textContent='Clicked'\">Save</button>") <>
          iframe("second", "<button>Other</button>")
      )

    locator = "iframe" |> frame_locator() |> by_role(:button, name: "Save")
    error = assert_raise Fluffy.OperationError, fn -> click(session, locator, timeout: 200) end
    assert error.operation == :click
    assert error.locator == locator
    assert error.backend == :playwright
    assert error.driver == :playwright
    assert %{error: %{name: "Error", message: message}} = error.cause
    assert message =~ "strict mode violation"

    selected_frame = "iframe" |> by_css() |> nth(0) |> content_frame()

    session
    |> expect(to_be_visible(by_role(selected_frame, :button, name: "Save")))
    |> click(by_role(selected_frame, :button, name: "Save"))
    |> expect(to_be_visible(by_role(selected_frame, :button, name: "Clicked")))
    |> expect(to_be_visible(by_role(frame_locator("#second"), :button, name: "Other")))
  end

  for driver <- [:static, :live] do
    @tag driver: driver
    test "#{driver} rejects traversal, including negated assertions and filter operands" do
      session =
        case unquote(driver) do
          :static -> session_for_html(:static, "<iframe id='child'></iframe>")
          :live -> :phoenix |> start_session(endpoint: Fluffy.TestWeb.Endpoint) |> visit("/live/three-heads")
        end

      locator = "#child" |> frame_locator() |> by_role(:button)

      for operation <- [
            fn -> click(session, locator) end,
            fn -> expect(session, not_(to_be_visible(locator))) end,
            fn -> expect(session, "missing" |> by_css() |> filter(has: locator) |> to_have_count(0)) end,
            fn -> expect(session, "missing" |> by_css() |> filter(has_not: locator) |> to_have_count(0)) end,
            fn -> click(session, "missing" |> by_css() |> filter(has_not: locator)) end
          ] do
        error = assert_raise Fluffy.CapabilityError, operation
        assert error.capability == :frames
        assert error.driver == unquote(driver)
      end

      error =
        assert_raise Fluffy.CapabilityError, fn ->
          expect(session, not_(to_be_checked(by_role(:checkbox), indeterminate: true)))
        end

      assert error.capability == :indeterminate_checked_state
      assert error.driver == unquote(driver)

      expect(session, to_have_count(by_css("#child"), if(unquote(driver) == :static, do: 1, else: 0)))
    end
  end

  defp browser_html(html), do: session_for_html(:playwright, html, base_url: Fluffy.TestServer.base_url())

  defp iframe(id, html) do
    escaped = html |> String.replace("&", "&amp;") |> String.replace("\"", "&quot;")
    ~s(<iframe id="#{id}" srcdoc="#{escaped}"></iframe>)
  end
end
