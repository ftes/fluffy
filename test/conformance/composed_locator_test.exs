defmodule Fluffy.Conformance.ComposedLocatorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
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

  defp with_html(driver, html, fun) do
    session =
      session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())

    fun.(session)
  end
end
