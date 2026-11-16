defmodule Fluffy.Conformance.ElementExpectationTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint
  alias Fluffy.Support.Web.ExpectationsLive

  @miss by_css("#absent")
  @timeout 5_000

  for driver <- [:static, :live, :playwright] do
    @tag driver: driver
    test "to_have_text compares normalized text with #{driver}", %{driver: driver} do
      spaced = by_css("#spaced")

      driver
      |> session()
      |> expect(to_have_text(spaced, "Sleeping dragon"))
      |> expect(to_have_text(spaced, "  Sleeping \n  dragon "))
      |> expect(to_have_text(spaced, "SLEEPING DRAGON", ignore_case: true))
      |> expect(not_(to_have_text(spaced, "Sleeping")))
      |> expect(to_have_text(by_css("#noise"), "Seen"))
      |> expect(to_have_text(by_css("#buttons"), "SendClear"))
      |> expect(to_have_text(by_css("#rendered"), "ShownConcealed"))
      |> expect(to_have_text(by_css("#plain"), ""))
    end

    # LiveViewTest serializes its tree without these nodes.
    if driver != :live do
      @tag driver: driver
      test "whitespace-only text between elements counts as text with #{driver}", %{driver: driver} do
        driver
        |> session()
        |> expect(to_have_text(by_css("#inline"), "a b"))
        |> expect(to_have_text(by_css("#inline"), ~r/^a b$/))
        |> expect(not_(to_be_empty(by_css("#area-blank"))))
      end
    end

    @tag driver: driver
    test "regular expressions see text as is with #{driver}", %{driver: driver} do
      spaced = by_css("#spaced")

      driver
      |> session()
      |> expect(to_have_text(spaced, ~r/Sleeping\n\s+dragon/))
      |> expect(not_(to_have_text(spaced, ~r/Sleeping dragon/)))
      |> expect(to_have_text(spaced, ~r/sleeping/, ignore_case: true))
      |> expect(not_(to_have_text(spaced, ~r/sleeping/i, ignore_case: false)))
      |> expect(to_contain_text(spaced, ~r/dragon/))
      |> expect(not_(to_contain_text(spaced, ~r/Sleeping dragon/)))
    end

    @tag driver: driver
    test "regular expressions run as JS RegExps with #{driver}", %{driver: driver} do
      spaced = by_css("#spaced")

      # `[^]` is JS-only syntax.
      driver
      |> session()
      |> expect(to_have_text(spaced, PlaywrightEx.RegExp.new("sleeping[^]+dragon", "i")))
      |> expect(to_have_count(filter(by_css("p"), has_text: PlaywrightEx.RegExp.new("Sleeping[^]+dragon")), 1))
      |> expect(to_have_count(by_role(:button, name: ~r/^Send$/), 1))
    end

    @tag driver: driver
    test "a PCRE-only regular expression raises with #{driver}", %{driver: driver} do
      session = session(driver)

      for {expectation, message} <- [
            {fn -> to_have_text(by_css("#spaced"), ~r/\ASleeping/) end, "\\A is not JS RegExp syntax: ~r/\\ASleeping/"},
            {fn -> to_have_count(by_role(:button, name: ~r/Send\z/), 1) end, "\\z is not JS RegExp syntax: ~r/Send\\z/"},
            {fn -> to_be_visible(filter(by_css("p"), has_text: ~r/(?i)dragon/)) end,
             "an inline option group (?...) is not JS RegExp syntax: ~r/(?i)dragon/"},
            {fn -> to_have_text(by_css("#spaced"), ~r/dragon/x) end,
             "Regex options [:extended] have no JS RegExp equivalent: ~r/dragon/x"}
          ] do
        assert_raise ArgumentError, message, fn -> expect(session, expectation.()) end
      end
    end

    @tag driver: driver
    test "to_contain_text finds a normalized substring with #{driver}", %{driver: driver} do
      spaced = by_css("#spaced")

      driver
      |> session()
      |> expect(to_contain_text(spaced, "ing drag"))
      |> expect(to_contain_text(spaced, " ing  \n drag "))
      |> expect(not_(to_contain_text(spaced, "ING DRAG")))
      |> expect(to_contain_text(spaced, "ING DRAG", ignore_case: true))
      |> expect(to_contain_text(spaced, ""))
      |> expect(not_(to_contain_text(spaced, "basilisk")))
    end

    @tag driver: driver
    test "the list form of text matches every element in order with #{driver}", %{driver: driver} do
      items = by_css(".item")

      driver
      |> session()
      |> expect(to_have_text(items, ["One", ~r/^Tw/, "Three"]))
      |> expect(not_(to_have_text(items, ["One", "Two"])))
      |> expect(not_(to_have_text(items, ["Three", "Two", "One"])))
      |> expect(to_contain_text(items, ["Thr"]))
      |> expect(to_contain_text(items, ["On", ~r/^Thr/]))
      |> expect(not_(to_contain_text(items, ["Three", "One"])))
      |> expect(to_have_text(@miss, []))
      |> expect(to_contain_text(@miss, []))
      |> expect(not_(to_have_text(@miss, ["One"])))
      |> expect(not_(to_contain_text(@miss, ["One"])))
    end

    @tag driver: driver
    test "to_have_attribute checks presence and raw values with #{driver}", %{driver: driver} do
      link = by_css("#link")

      driver
      |> session()
      |> expect(to_have_attribute(link, "href"))
      |> expect(to_have_attribute(link, "href", timeout: @timeout))
      |> expect(to_have_attribute(link, "data-flag", ""))
      |> expect(not_(to_have_attribute(link, "open")))
      |> expect(not_(to_have_attribute(link, "open", "x")))
      |> expect(to_have_attribute(link, "href", "/chamber"))
      |> expect(to_have_attribute(link, "href", ~r/^\/ch/))
      |> expect(to_have_attribute(link, "data-note", "Lumos  Maxima"))
      |> expect(not_(to_have_attribute(link, "data-note", "Lumos Maxima")))
      |> expect(not_(to_have_attribute(link, "href", "/CHAMBER")))
      |> expect(to_have_attribute(by_css("#vector"), "viewBox", "0 0 10 10"))
      |> expect(not_(to_have_attribute(by_css("#vector"), "viewbox")))
      |> expect(to_have_attribute(link, "href", "/CHAMBER", ignore_case: true))
      |> expect(to_have_attribute(link, "href", ~r/CHAMBER/, ignore_case: true))
    end

    @tag driver: driver
    test "to_have_class matches the whole attribute with #{driver}", %{driver: driver} do
      classy = by_css("#classy")

      driver
      |> session()
      |> expect(to_have_class(classy, "middle  selected row"))
      |> expect(not_(to_have_class(classy, "middle selected row")))
      |> expect(not_(to_have_class(classy, "selected")))
      |> expect(to_have_class(classy, ~r/(^|\s)selected(\s|$)/))
      |> expect(to_have_class(by_css("#plain"), ""))
      |> expect(to_have_class(by_css(".item"), ["item first", ~r/^item$/, "item last"]))
      |> expect(not_(to_have_class(by_css(".item"), ["item first", "item"])))
    end

    @tag driver: driver
    test "to_contain_class checks individual classes with #{driver}", %{driver: driver} do
      classy = by_css("#classy")

      driver
      |> session()
      |> expect(to_contain_class(classy, "row"))
      |> expect(to_contain_class(classy, " row   middle "))
      |> expect(not_(to_contain_class(classy, "sele")))
      |> expect(not_(to_contain_class(classy, "row absent")))
      |> expect(to_contain_class(by_css(".item"), ["first", "item", "last"]))
      |> expect(not_(to_contain_class(by_css(".item"), ["first", "last"])))
    end

    @tag driver: driver
    test "to_have_id reads the element id with #{driver}", %{driver: driver} do
      driver
      |> session()
      |> expect(to_have_id(by_css("#link"), "link"))
      |> expect(to_have_id(by_css("#link"), ~r/^li/))
      |> expect(not_(to_have_id(by_css("#link"), "LINK")))
      |> expect(to_have_id(by_css(".first"), ""))
    end

    @tag driver: driver
    test "to_be_attached requires a matching element with #{driver}", %{driver: driver} do
      concealed = by_css("#concealed")

      driver
      |> session()
      |> expect(to_be_attached(concealed))
      |> expect(not_(to_be_attached(@miss)))
      |> expect(to_be_attached(@miss, attached: false))
      |> expect(not_(to_be_attached(concealed, attached: false)))
      |> refute_passes(not_(to_be_attached(concealed)))
      |> refute_passes(to_be_attached(@miss))
      |> refute_passes(to_be_attached(concealed, attached: false))
      |> refute_passes(not_(to_be_attached(@miss, attached: false)))
    end

    @tag driver: driver
    test "to_be_hidden passes when nothing matches with #{driver}", %{driver: driver} do
      driver
      |> session()
      |> expect(to_be_hidden(by_css("#concealed")))
      |> expect(to_be_hidden(@miss))
      |> expect(not_(to_be_visible(@miss)))
      |> expect(not_(to_be_hidden(by_css("#link"))))
      |> refute_passes(to_be_hidden(by_css("#link")))
      |> refute_passes(not_(to_be_hidden(@miss)))
      |> refute_passes(not_(to_be_hidden(by_css("#concealed"))))
    end

    @tag driver: driver
    test "hidden ancestors and hidden inputs are not visible with #{driver}", %{driver: driver} do
      for hidden <- [by_css("#nested-concealed"), by_css("#hidden-input")] do
        driver
        |> session()
        |> expect(to_be_hidden(hidden))
        |> expect(not_(to_be_visible(hidden)))
        |> expect(hidden |> filter(visible: true) |> to_have_count(0))
        |> expect(hidden |> filter(visible: false) |> to_have_count(1))
      end
    end

    @tag driver: driver
    test "to_be_empty reads values and text with #{driver}", %{driver: driver} do
      session = session(driver)

      session
      |> expect(to_be_empty(by_css("#plain")))
      |> expect(to_be_empty(by_css("#blank")))
      |> expect(to_be_empty(by_css("#comment")))
      |> expect(to_be_empty(by_css("#vacant")))
      |> expect(to_be_empty(by_css("#area")))
      |> expect(not_(to_be_empty(by_css("#filled"))))
      |> expect(not_(to_be_empty(by_css("#area-filled"))))
      |> expect(not_(to_be_empty(by_css("#link"))))
      |> fill(by_css("#vacant"), "typed")
      |> expect(not_(to_be_empty(by_css("#vacant"))))
      |> refute_passes(to_be_empty(by_css("#link")))
      |> refute_passes(not_(to_be_empty(by_css("#plain"))))
    end

    @tag driver: driver
    test "neither a value matcher nor its negation passes without an element with #{driver}", %{driver: driver} do
      driver
      |> session()
      |> refute_passes(to_have_text(@miss, "x"))
      |> refute_passes(not_(to_have_text(@miss, "x")))
      |> refute_passes(not_(to_contain_text(@miss, "x")))
      |> refute_passes(not_(to_have_attribute(@miss, "href")))
      |> refute_passes(not_(to_have_attribute(@miss, "href", "x")))
      |> refute_passes(not_(to_have_class(@miss, "x")))
      |> refute_passes(not_(to_contain_class(@miss, "x")))
      |> refute_passes(not_(to_have_id(@miss, "x")))
      |> refute_passes(not_(to_be_empty(@miss)))
      |> refute_passes(to_be_empty(@miss))
    end

    @tag driver: driver
    test "single-element matchers reject an ambiguous locator with #{driver}", %{driver: driver} do
      items = by_css(".item")

      expectations = [
        to_have_text(items, "One"),
        to_contain_text(items, "One"),
        to_have_attribute(items, "class"),
        to_have_attribute(items, "class", "item"),
        to_have_class(items, "item"),
        to_contain_class(items, "item"),
        to_have_id(items, ""),
        to_be_attached(items),
        to_be_hidden(items),
        to_be_empty(items)
      ]

      session = session(driver)

      for expectation <- expectations, expectation <- [expectation, not_(expectation)] do
        assert_raise ExUnit.AssertionError, ~r/strict mode violation|exactly one element/, fn ->
          expect(session, expectation, timeout: 50)
        end
      end
    end
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "the element expectations retry a changing LiveView with #{driver}", %{driver: driver} do
      session = start_session(driver, base_url: Server.base_url(), endpoint: Endpoint)

      session
      |> visit("/live/expectations?delay=25")
      |> expect(to_have_text(by_test_id("text"), "ready"), timeout: @timeout)
      |> expect(not_(to_contain_text(by_test_id("contain-text"), "waiting")), timeout: @timeout)
      |> expect(to_contain_text(by_test_id("contain-text"), "now ready"), timeout: @timeout)
      |> expect(to_have_attribute(by_test_id("attribute"), "data-state", "ready"), timeout: @timeout)
      |> expect(to_have_class(by_test_id("class"), "ready"), timeout: @timeout)
      |> expect(to_contain_class(by_test_id("contain-class"), "ready"), timeout: @timeout)
      |> expect(to_have_id(by_test_id("id"), "ready"), timeout: @timeout)
      |> expect(to_be_attached(by_test_id("attached")), timeout: @timeout)
      |> expect(to_be_hidden(by_test_id("hidden")), timeout: @timeout)
      |> expect(to_be_empty(by_test_id("empty")), timeout: @timeout)
    end
  end

  @tag driver: :live
  test "within resolves nth per parent on a LiveView" do
    item = by_css("li")

    :live
    |> session()
    |> expect(item |> nth(1) |> within(by_css("ul")) |> to_have_text("Two"))
    |> expect(to_have_count(within(item, by_css("ul")), 3))
  end

  @tag driver: :live
  test "a Live expectation fails once its timeout runs out" do
    session = session(:live)
    started_at = System.monotonic_time(:millisecond)

    assert_raise ExUnit.AssertionError, ~r/to have text "x"/, fn ->
      expect(session, to_have_text(by_css("#link"), "x"), timeout: 100)
    end

    assert System.monotonic_time(:millisecond) - started_at >= 100
  end

  @tag driver: :static
  test "a Static expectation does not wait" do
    session = session(:static)
    started_at = System.monotonic_time(:millisecond)

    assert_raise ExUnit.AssertionError, fn ->
      expect(session, to_have_text(by_css("#link"), "x"), timeout: @timeout)
    end

    assert System.monotonic_time(:millisecond) - started_at < @timeout
  end

  @tag driver: :playwright
  test "use_inner_text reads rendered text on Playwright" do
    rendered = by_css("#rendered")

    :playwright
    |> session()
    |> expect(to_have_text(rendered, "Shown", use_inner_text: true))
    |> expect(to_contain_text(rendered, "Shown", use_inner_text: true))
    |> expect(not_(to_have_text(rendered, "Shown")))
    |> expect(not_(to_contain_text(rendered, "Concealed", use_inner_text: true)))
  end

  for driver <- [:static, :live] do
    @tag driver: driver
    test "use_inner_text needs a browser with #{driver}", %{driver: driver} do
      session = session(driver)

      for expectation <- [
            to_have_text(by_css("#link"), "Go", use_inner_text: true),
            to_contain_text(by_css("#link"), "Go", use_inner_text: false)
          ] do
        error = assert_raise Fluffy.CapabilityError, fn -> expect(session, expectation) end
        assert error.capability == :computed_browser_semantics
      end
    end
  end

  test "constructors reject values a matcher cannot compare" do
    assert_raise ArgumentError, fn -> to_have_text(by_css("p"), ["One", 2]) end
    assert_raise ArgumentError, fn -> to_contain_class(by_css("p"), [~r/row/]) end
    assert_raise NimbleOptions.ValidationError, fn -> to_have_class(by_css("p"), "x", ignore_case: true) end
  end

  defp session(:live) do
    :phoenix
    |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
    |> visit("/live/expectations")
  end

  defp session(driver), do: session_for_html(driver, ExpectationsLive.markup(), base_url: Server.base_url())

  defp refute_passes(session, expectation) do
    assert_raise ExUnit.AssertionError, fn -> expect(session, expectation, timeout: 50) end
    session
  end
end
