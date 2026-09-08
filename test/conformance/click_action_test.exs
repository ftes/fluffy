defmodule Fluffy.Conformance.ClickActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    @tag :webkit_difference

    test "click focuses a button with #{driver}" do
      with_html(unquote(driver), "<button>Save</button>", fn session ->
        session
        |> click(by_role(:button, name: "Save"))
        |> expect(focused(by_role(:button, name: "Save")))
      end)
    end

    @tag driver: driver
    test "click toggles a checkbox property with #{driver}" do
      checkbox = by_role(:checkbox, name: "Updates")
      html = ~s(<label for="updates">Updates</label><input id="updates" type="checkbox">)

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(not_(checked(checkbox)))
        |> click(checkbox)
        |> expect(checked(checkbox))
        |> click(checkbox)
        |> expect(not_(checked(checkbox)))
      end)
    end

    @tag driver: driver
    test "click requires exactly one target with #{driver}" do
      with_html(unquote(driver), "<button>Save</button><button>Save draft</button>", fn session ->
        assert_raise Fluffy.StrictnessError, ~r/it matched 2/, fn ->
          click(session, by_role(:button, name: "Save"), timeout: 5)
        end
      end)
    end

    @tag driver: driver
    test "click rejects a disabled button with #{driver}" do
      with_html(unquote(driver), "<button disabled>Save</button>", fn session ->
        error =
          assert_raise Fluffy.ActionabilityError, ~r/disabled/, fn ->
            click(session, by_role(:button, name: "Save"), timeout: 5)
          end

        assert error.action == :click
        assert error.reason == :disabled
      end)
    end

    @tag driver: driver
    test "click rejects a structurally hidden target with #{driver}" do
      with_html(unquote(driver), "<button hidden>Save</button>", fn session ->
        assert_raise Fluffy.ActionabilityError, ~r/hidden/, fn ->
          click(session, by_css("button"), timeout: 5)
        end
      end)
    end
  end

  test "Static ignores CSS-dependent click actionability" do
    session = session_for_html(:static, ~s(<button style="display: none">Save</button>))

    session
    |> click(by_css("button"))
    |> expect(focused(by_css("button")))
  end

  test "Static ignores data-confirm before its structural click action" do
    session = session_for_html(:static, ~s(<button data-confirm="Proceed?">Confirm</button>))

    session
    |> click(by_role(:button, name: "Confirm", exact: true))
    |> expect(focused(by_role(:button, name: "Confirm", exact: true)))
  end

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "clicking a link hands navigation to the #{driver} backend" do
      session =
        start_session(unquote(driver),
          base_url: Fluffy.TestServer.base_url(),
          endpoint: Fluffy.TestWeb.Endpoint
        )

      session
      |> visit("/actions/click")
      |> click(by_role(:link, name: "Enter the chamber"))
      |> expect(visible(by_text("The guardian sleeps")))
    end
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
