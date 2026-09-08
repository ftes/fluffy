defmodule Fluffy.Conformance.SelectOptionActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "select_option matches a single option by value or label with #{driver}" do
      field = by_label("Country")

      html = """
      <label for="country">Country</label>
      <select id="country">
        <option value="us">United States</option>
        <option value="gb">United Kingdom</option>
      </select>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(to_have_value(field, "us"))
        |> select_option(field, "gb")
        |> expect(to_have_value(field, "gb"))
        |> select_option(field, "United States")
        |> expect(to_have_value(field, "us"))
      end)
    end

    @tag driver: driver
    test "select_option replaces a multiple select in document order with #{driver}" do
      field = by_label("Colours")

      html = """
      <label for="colours">Colours</label>
      <select id="colours" multiple>
        <option value="red" selected>Red</option>
        <option value="green">Green</option>
        <option value="blue">Blue</option>
      </select>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(to_have_values(field, ["red"]))
        |> select_option(field, ["blue", "green"])
        |> expect(to_have_values(field, ["green", "blue"]))
      end)
    end

    @tag driver: driver
    test "successive multiple-select actions replace rather than accumulate with #{driver}" do
      field = by_label("Races")

      html = """
      <label for="races">Races</label>
      <select id="races" multiple>
        <option value="elf">Elf</option>
        <option value="dwarf">Dwarf</option>
        <option value="human">Human</option>
      </select>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> select_option(field, ["elf", "dwarf"])
        |> expect(to_have_values(field, ["elf", "dwarf"]))
        |> select_option(field, "human")
        |> expect(to_have_values(field, ["human"]))
      end)
    end

    @tag driver: driver
    test "select_option supports an explicit label match with #{driver}" do
      field = by_label("Plan")
      html = ~s(<label>Plan<select><option value="pro">Professional</option></select></label>)

      with_html(unquote(driver), html, fn session ->
        session
        |> select_option(field, %{label: "Professional"})
        |> expect(to_have_value(field, "pro"))
      end)
    end

    @tag driver: driver
    test "select_option rejects a disabled option with #{driver}" do
      html = ~s(<select aria-label="Plan"><option disabled>Unavailable</option></select>)

      with_html(unquote(driver), html, fn session ->
        assert_raise Fluffy.ActionabilityError, ~r/disabled option/, fn ->
          select_option(session, by_label("Plan"), "Unavailable", timeout: 5)
        end
      end)
    end

    @tag driver: driver
    test "select defaults to the first enabled option and respects list size with #{driver}" do
      html = """
      <label>Plan
        <select>
          <option disabled value="unavailable">Unavailable</option>
          <optgroup disabled><option value="legacy">Legacy</option></optgroup>
          <option value="current">Current</option>
        </select>
      </label>
      <label>Queue
        <select size="2"><option value="first">First</option><option value="second">Second</option></select>
      </label>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect("Plan" |> by_label() |> to_have_value("current"))
        |> expect("Queue" |> by_label() |> to_have_value(""))
      end)
    end

    @tag driver: driver
    test "select_option rejects an option disabled by its optgroup with #{driver}" do
      html =
        ~s(<select aria-label="Plan"><optgroup disabled><option>Legacy</option></optgroup></select>)

      with_html(unquote(driver), html, fn session ->
        assert_raise Fluffy.ActionabilityError, ~r/disabled option/, fn ->
          select_option(session, by_label("Plan"), "Legacy", timeout: 5)
        end
      end)
    end
  end

  @tag driver: :playwright
  test "the browser oracle fixes select input/change ordering" do
    html = """
    <select aria-label="Plan"
      oninput="events.value += 'input:' + this.value + '|'"
      onchange="events.value += 'change:' + this.value + '|'">
      <option value="free">Free</option>
      <option value="pro">Pro</option>
    </select>
    <input id="events" aria-label="Events" value="">
    """

    with_html(:playwright, html, fn session ->
      session
      |> select_option(by_label("Plan"), "pro")
      |> expect("Events" |> by_label() |> to_have_value("input:pro|change:pro|"))
    end)
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
