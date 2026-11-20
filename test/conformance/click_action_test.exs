defmodule Fluffy.Conformance.ClickActionTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "click with timeout: 0 makes one attempt on Phoenix and is rejected on Playwright with #{driver}",
         %{driver: driver} do
      session =
        driver
        |> start_session()
        |> visit("/live/three-heads")

      flute = by_role(:button, name: "Play the flute")

      if driver == :phoenix do
        session
        |> click(flute, timeout: 0)
        |> expect("Sleeping heads: 1" |> by_text() |> to_be_visible())
      else
        assert_raise ArgumentError, ~r/timeout: 0 means check once.*pass a positive timeout/, fn ->
          click(session, flute, timeout: 0)
        end

        expect(session, "Sleeping heads: 0" |> by_text() |> to_be_visible(), timeout: 0)
      end
    end
  end

  for driver <- Drivers.html() do
    @tag driver: driver
    test "click toggles a checkbox property with #{driver}" do
      checkbox = by_role(:checkbox, name: "Updates")
      html = ~s(<label for="updates">Updates</label><input id="updates" type="checkbox">)

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(not_(to_be_checked(checkbox)))
        |> click(checkbox)
        |> expect(to_be_checked(checkbox))
        |> click(checkbox)
        |> expect(not_(to_be_checked(checkbox)))
      end)
    end

    @tag driver: driver
    test "click selects a radio and keeps it selected with #{driver}" do
      small = by_role(:radio, name: "Small")
      large = by_role(:radio, name: "Large")

      html =
        ~s(<label><input type="radio" name="size" checked>Small</label><label><input type="radio" name="size">Large</label>)

      with_html(unquote(driver), html, fn session ->
        session
        |> click(large)
        |> expect(to_be_checked(large))
        |> expect(not_(to_be_checked(small)))
        |> click(large)
        |> expect(to_be_checked(large))
      end)
    end

    @tag driver: driver
    test "click requires exactly one target with #{driver}" do
      with_html(unquote(driver), "<button>Save</button><button>Save draft</button>", fn session ->
        assert_action_error(session, Fluffy.StrictnessError, ~r/it matched 2/, fn ->
          click(session, by_role(:button, name: "Save"), timeout: 5)
        end)
      end)
    end

    @tag driver: driver
    test "click rejects a disabled button with #{driver}" do
      with_html(unquote(driver), "<button disabled>Save</button>", fn session ->
        error =
          assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled/, fn ->
            click(session, by_role(:button, name: "Save"), timeout: 5)
          end)

        assert error.operation == :click
        if Fluffy.Session.current_driver(session) != :playwright, do: assert(error.cause.reason == :disabled)
      end)
    end

    # Like Playwright, text inside a button takes the button's enabled state.
    @tag driver: driver
    test "click rejects text inside a disabled button with #{driver}" do
      html = """
      <form method="get" action="/search">
        <button disabled><span>Search</span></button>
        <fieldset disabled><button><span>Search all</span></button></fieldset>
      </form>
      """

      with_html(unquote(driver), html, fn session ->
        for text <- ["Search", "Search all"] do
          span = by_text(text, exact: true)
          expect(session, to_be_disabled(span))

          assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled/, fn ->
            click(session, span, timeout: 5)
          end)
        end
      end)
    end

    # Like a browser, a click on a label clicks its control, nested or by `for`.
    @tag driver: driver
    test "clicking a label toggles its checkbox and selects its radio with #{driver}" do
      html = """
      <label for="permission">Hogsmeade permission</label><input id="permission" type="checkbox">
      <label><input type="radio" name="house" checked> Slytherin</label>
      <label><input type="radio" name="house"> <span>Gryffindor</span></label>
      <label>Patronus <input type="text" value="Stag"></label>
      """

      permission = by_role(:checkbox, name: "Hogsmeade permission")

      with_html(unquote(driver), html, fn session ->
        session
        |> click(by_text("Hogsmeade permission", exact: true))
        |> expect(to_be_checked(permission))
        |> click(by_text("Hogsmeade permission", exact: true))
        |> expect(not_(to_be_checked(permission)))
        |> click(by_text("Gryffindor", exact: true))
        |> expect(:radio |> by_role(name: "Gryffindor") |> to_be_checked())
        |> expect(:radio |> by_role(name: "Slytherin") |> to_be_checked(checked: false))
        |> click(by_text("Patronus"))
        |> expect(:textbox |> by_role(name: "Patronus") |> to_have_value("Stag"))
      end)
    end

    # Like Playwright's retarget(..., "follow-label"), a label takes its
    # control's enabled state, so a click on it waits for the control.
    @tag driver: driver
    test "a label takes its control's enabled state with #{driver}" do
      html = """
      <label><input type="checkbox" disabled> Accept</label>
      <label for="cloak">Cloak</label><fieldset disabled><input id="cloak" type="checkbox"></fieldset>
      """

      with_html(unquote(driver), html, fn session ->
        for text <- ["Accept", "Cloak"] do
          label = by_text(text, exact: true)
          expect(session, to_be_disabled(label))

          assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled|not enabled/, fn ->
            click(session, label, timeout: 5)
          end)
        end
      end)
    end

    # A label in a button takes the button's enabled state, as in Playwright,
    # and its click reaches a disabled control, which a browser doesn't click.
    @tag driver: driver
    test "a label's click doesn't click its disabled control with #{driver}" do
      html = """
      <button type="button"><label for="vow">Unbreakable vow</label></button>
      <input id="vow" type="checkbox" disabled>
      """

      with_html(unquote(driver), html, fn session ->
        label = by_text("Unbreakable vow", exact: true)

        session
        |> expect(to_be_enabled(label))
        |> click(label)
        |> expect(:checkbox |> by_role(name: "Unbreakable vow") |> to_be_checked(checked: false))
      end)
    end

    # A click on a label's control, or on interactive content in the label,
    # stays there.
    @tag driver: driver
    test "a click inside a label's control or other content stays there with #{driver}" do
      html = """
      <label for="owl">Owl <select><option>Hedwig</option></select></label>
      <input id="owl" type="checkbox">
      <label><input type="checkbox" checked> Broom</label>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> click(by_role(:combobox))
        |> expect(:checkbox |> by_role(name: "Owl") |> to_be_checked(checked: false))
        |> click(by_role(:checkbox, name: "Broom"))
        |> expect(:checkbox |> by_role(name: "Broom") |> to_be_checked(checked: false))
      end)
    end

    # Like Playwright, a disabled attribute or fieldset disables only a native form control.
    @tag driver: driver
    test "click ignores a disabled attribute outside native form controls with #{driver}" do
      html = """
      <div role="button" disabled>Go</div>
      <button type="button"><span disabled>Search</span></button>
      <fieldset disabled><div role="button">Stay</div></fieldset>
      """

      with_html(unquote(driver), html, fn session ->
        for target <- [by_role(:button, name: "Go"), by_text("Search", exact: true), by_role(:button, name: "Stay")] do
          session |> expect(to_be_enabled(target)) |> click(target)
        end
      end)
    end

    @tag driver: driver
    test "click rejects a structurally hidden target with #{driver}" do
      with_html(unquote(driver), "<button hidden>Save</button>", fn session ->
        assert_action_error(session, Fluffy.ActionabilityError, ~r/hidden/, fn ->
          click(session, by_css("button"), timeout: 5)
        end)
      end)
    end
  end

  test "Static ignores CSS-dependent click actionability" do
    session = session_for_html(:static, ~s(<button style="display: none">Save</button>))

    session
    |> click(by_css("button"))
    |> expect("button" |> by_css() |> to_have_count(1))
  end

  test "Static ignores data-confirm before its structural click action" do
    session = session_for_html(:static, ~s(<button data-confirm="Proceed?">Confirm</button>))

    session
    |> click(by_role(:button, name: "Confirm", exact: true))
    |> expect(:button |> by_role(name: "Confirm", exact: true) |> to_have_count(1))
  end

  for driver <- Drivers.backends() do
    @tag driver: driver
    test "clicking a link hands navigation to the #{driver} backend" do
      session =
        start_session(unquote(driver))

      session
      |> visit("/actions/click")
      |> click(by_role(:link, name: "Enter the chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end
  end
end
