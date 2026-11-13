defmodule Fluffy.Conformance.ClickActionTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.Server
  alias Fluffy.Support.Web.Endpoint

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "click with timeout: 0 makes one attempt on Phoenix and is rejected on Playwright with #{driver}",
         %{driver: driver} do
      session =
        driver
        |> start_session(base_url: Server.base_url(), endpoint: Endpoint)
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

  for driver <- [:static, :playwright] do
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

    # Known difference: Playwright follows a label to its control, for the
    # enabled state as for the click's activation. Phoenix treats a label as a
    # plain element, so its text is enabled and clicking it does nothing (#134).
    @tag driver: driver
    test "a label takes its control's state and activation only on Playwright with #{driver}" do
      html = """
      <label><input type="checkbox" disabled> Accept</label>
      <label for="permission">Hogsmeade permission</label><input id="permission" type="checkbox">
      """

      playwright? = unquote(driver) == :playwright

      with_html(unquote(driver), html, fn session ->
        accept = by_text("Accept", exact: true)

        session
        |> expect(if(playwright?, do: to_be_disabled(accept), else: to_be_enabled(accept)))
        |> click(by_text("Hogsmeade permission", exact: true))
        |> expect(:checkbox |> by_role(name: "Hogsmeade permission") |> to_be_checked(checked: playwright?))
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

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "clicking a link hands navigation to the #{driver} backend" do
      session =
        start_session(unquote(driver),
          base_url: Server.base_url(),
          endpoint: Endpoint
        )

      session
      |> visit("/actions/click")
      |> click(by_role(:link, name: "Enter the chamber"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Server.base_url())
    fun.(session)
  end
end
