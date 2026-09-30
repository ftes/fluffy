defmodule Fluffy.Conformance.ComposedLocatorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "intersections and unions use current checked state on either side with #{driver}", %{driver: driver} do
      driver
      |> session_for_html("""
      <label><input id="enabled" type="checkbox">Enabled</label>
      <select aria-label="Plan"><option>Free</option><option>Pro</option></select>
      """)
      |> check(by_label("Enabled"))
      |> select_option(by_label("Plan"), "Pro")
      |> expect(to_have_count(and_(by_label("Enabled"), by_css(":checked")), 1))
      |> expect(to_have_count(and_(by_css(":checked"), by_label("Enabled")), 1))
      |> expect(to_have_count(or_(by_css("#missing"), by_css("option:checked")), 1))
      |> expect(to_have_count(or_(by_css("option:checked"), by_css("#missing")), 1))
      |> expect(
        "option"
        |> by_css()
        |> and_(by_css(":checked"))
        |> filter(has_text: "Pro", exact: true)
        |> to_have_count(1)
      )
      |> uncheck(and_(by_label("Enabled"), by_css(":checked")))
      |> expect(to_have_count(and_(by_label("Enabled"), by_css(":checked")), 0))
    end

    @tag driver: driver
    test "exact text filters retain the candidate and normalize its complete text with #{driver}" do
      session =
        session_for_html(unquote(driver), """
        <div data-candidate>Day</div>
        <div data-candidate>day</div>
        <div data-candidate><span>Day</span> type</div>
        <div data-candidate hidden> <span> Day </span> </div>
        <div data-candidate>Flat day</div>
        """)

      session
      |> expect(to_have_count(filter(by_css("[data-candidate]"), has_text: " Day ", exact: true), 2))
      |> expect(to_have_count(filter(by_css("[data-candidate]"), has_not_text: "Day", exact: true), 3))
      |> expect(to_have_count(filter(by_css("[data-candidate]"), has_text: "Day"), 5))
      |> expect(to_have_count(filter(by_css("[data-candidate]"), exact: true, has_text: "Day type"), 1))
    end

    @tag driver: driver
    test "chains a child locator within its parent scope with #{driver}", %{driver: driver} do
      html = """
      <section id="billing"><button>Save</button></section>
      <section id="profile"><button>Save</button></section>
      """

      locator = "#billing" |> by_css() |> by_role(:button, name: "Save")

      with_html(driver, html, fn session -> expect(session, to_have_count(locator, 1)) end)
    end

    @tag driver: driver
    test "does not let a child locator escape its parent scope with #{driver}", %{driver: driver} do
      html = "<section id=empty></section><button>Outside</button>"
      locator = "#empty" |> by_css() |> by_role(:button, name: "Outside")

      with_html(driver, html, fn session -> expect(session, to_have_count(locator, 0)) end)
    end

    @tag driver: driver
    test "filters candidates by descendant text with #{driver}", %{driver: driver} do
      html = "<ul><li>Product 1</li><li>Product 2</li></ul>"
      locator = "li" |> by_css() |> filter(has_text: "Product 2")

      with_html(driver, html, fn session -> expect(session, to_have_count(locator, 1)) end)
    end

    @tag driver: driver
    test "filters candidates by a relative child locator with #{driver}", %{driver: driver} do
      html = """
      <article><h2>Available</h2><button>Buy</button></article>
      <article><h2>Unavailable</h2></article>
      """

      locator = "article" |> by_css() |> filter(has: by_role(:button, name: "Buy"))

      with_html(driver, html, fn session -> expect(session, to_have_count(locator, 1)) end)
    end

    @tag driver: driver
    test "uses zero-based nth and first/last positions with #{driver}", %{driver: driver} do
      html = "<ol><li>Zero</li><li>One</li><li>Two</li></ol>"

      with_html(driver, html, fn session ->
        session
        |> expect("li" |> by_css() |> first() |> by_text("Zero", exact: true) |> to_have_count(1))
        |> expect("li" |> by_css() |> nth(1) |> by_text("One", exact: true) |> to_have_count(1))
        |> expect("li" |> by_css() |> last() |> by_text("Two", exact: true) |> to_have_count(1))
        |> expect("li" |> by_css() |> nth(9) |> to_have_count(0))
      end)
    end

    @tag driver: driver
    test "scopes repeated rows to one of several tables with #{driver}", %{driver: driver} do
      html = """
      <table aria-label="Orders">
        <tbody><tr><td>Shared row</td><td>Order 42</td></tr></tbody>
      </table>
      <table aria-label="Invoices">
        <tbody><tr><td>Shared row</td><td>Invoice 9</td></tr></tbody>
      </table>
      """

      orders = by_role(:table, name: "Orders", exact: true)
      shared_order_row = orders |> by_role(:row) |> filter(has_text: "Shared row")

      with_html(driver, html, fn session ->
        session
        |> expect(to_have_count(shared_order_row, 1))
        |> expect(shared_order_row |> by_text("Order 42", exact: true) |> to_have_count(1))
        |> expect(shared_order_row |> by_text("Invoice 9", exact: true) |> to_have_count(0))
      end)
    end
  end

  test "composed locators are plain serializable values" do
    locator =
      "article"
      |> by_css()
      |> filter(has: by_role(:button, name: "Buy"), has_text: "Available")
      |> nth(1)

    assert locator |> :erlang.term_to_binary() |> :erlang.binary_to_term() == locator
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "intersects CSS and associated labels on the same control with #{driver}", %{driver: driver} do
      session =
        session_for_html(driver, """
        <label for="email">Email</label><input id="email">
        <label for="other">Email</label><input id="other">
        """)

      target = "#email" |> by_css() |> and_(by_label("Email", exact: true))

      session
      |> fill(target, "reader@example.com")
      |> expect(to_have_value(target, "reader@example.com"))
      |> expect("label" |> by_css() |> and_(by_label("Email")) |> to_have_count(0))
      |> set_html("<label for='other'>Email</label><input id='other'>")
      |> expect(to_have_count(target, 0))
    end

    @tag driver: driver
    test "retains node identity, order, composition and strictness with #{driver}", %{driver: driver} do
      session = session_for_html(driver, "<button>Save</button><button>Save</button><button>Other</button>")
      buttons = by_css("button")
      saves = and_(buttons, by_text("Save", exact: true))

      session
      |> expect(to_have_count(saves, 2))
      |> expect(saves |> first() |> and_(nth(buttons, 1)) |> to_have_count(0))
      |> expect(saves |> last() |> and_(nth(buttons, 1)) |> to_have_count(1))
      |> expect(buttons |> first() |> and_(nth(buttons, 1)) |> to_have_count(0))
      |> expect(saves |> and_(by_text("Other")) |> to_have_count(0))

      error = assert_raise Fluffy.OperationError, fn -> click(session, saves, timeout: 1_000) end
      assert error.message =~ "and_(by_text"
      assert error.message =~ if(driver == :playwright, do: "strict mode violation", else: "matched 2")
    end

    @tag driver: driver
    test "resolves the right side from the query root, including inside has filters with #{driver}", %{driver: driver} do
      session =
        session_for_html(driver, """
        <section id="one"><button>Save</button></section>
        <section id="two"><button>Save</button></section>
        """)

      session
      |> expect("section" |> by_css() |> and_(by_role(:button)) |> to_have_count(0))
      |> expect("#two button" |> by_css() |> and_(first(by_role(:button))) |> to_have_count(0))
      |> expect(
        "section"
        |> by_css()
        |> filter(has: "button" |> by_css() |> and_(first(by_role(:button))))
        |> to_have_count(2)
      )
      |> expect(
        "section"
        |> by_css()
        |> filter(has_not: "button" |> by_css() |> and_(by_text("Save")))
        |> to_have_count(0)
      )
      |> expect("section" |> by_css() |> and_(by_css("#two")) |> by_role(:button) |> to_have_count(1))
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "intersections act on and re-resolve LiveView renders with #{driver}", %{driver: driver} do
      session = start_session(driver, base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
      flute = "button" |> by_css() |> and_(by_role(:button, name: "Play the flute"))

      session
      |> visit("/live/three-heads")
      |> click(flute)
      |> expect(to_be_visible(by_text("Sleeping heads: 1")))
      |> click(flute)
      |> expect(to_be_visible(by_text("Sleeping heads: 2")))
    end
  end

  test "intersections remain serializable and describe both operands" do
    locator = "#email" |> by_css() |> and_(by_label("Email", exact: true))
    assert locator |> :erlang.term_to_binary() |> :erlang.binary_to_term() == locator
    assert Fluffy.Locator.describe(locator) == ~s{by_css("#email") |> and_(by_label("Email", exact: true))}
  end

  defp with_html(driver, html, fun) do
    session =
      session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())

    fun.(session)
  end
end
