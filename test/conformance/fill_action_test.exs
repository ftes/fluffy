defmodule Fluffy.Conformance.FillActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  @set_value_input_cases [
    {"color", "#123456", ""},
    {"date", "2025-01-02", ""},
    {"datetime-local", "2025-01-02T03:04", ""},
    {"month", "2025-01", ""},
    {"range", "7", ~s(min="0" max="10")},
    {"time", "03:04", ""},
    {"week", "2025-W01", ""}
  ]

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "fill replaces an input's current value with #{driver}" do
      field = by_label("Email")
      html = ~s(<label for="email">Email</label><input id="email" value="old@example.com">)

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(value(field, "old@example.com"))
        |> fill(field, "new@example.com")
        |> expect(value(field, "new@example.com"))
        |> expect(focused(field))
      end)
    end

    @tag driver: driver
    test "fill accepts an empty textarea value with #{driver}" do
      field = by_label("Notes")
      html = ~s(<label for="notes">Notes</label><textarea id="notes">Initial notes</textarea>)

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(value(field, "Initial notes"))
        |> fill(field, "")
        |> expect(value(field, ""))
      end)
    end

    @tag driver: driver
    test "fill treats a valueless contenteditable attribute as editable with #{driver}" do
      editor = by_role(:textbox, name: "Editor")
      html = ~s(<div role="textbox" aria-label="Editor" contenteditable></div>)

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(editable(editor))
        |> fill(editor, "Updated")
        |> expect(focused(editor))
      end)
    end

    @tag driver: driver
    test "fill requires exactly one target with #{driver}" do
      with_html(unquote(driver), ~s(<input title="Name"><input title="Name">), fn session ->
        assert_raise Fluffy.StrictnessError, ~r/it matched 2/, fn ->
          fill(session, by_title("Name"), "Ada", timeout: 5)
        end
      end)
    end

    @tag driver: driver
    test "fill rejects a disabled field with #{driver}" do
      with_html(unquote(driver), ~s(<input aria-label="Name" disabled>), fn session ->
        assert_raise Fluffy.ActionabilityError, ~r/disabled/, fn ->
          fill(session, by_label("Name"), "Ada", timeout: 5)
        end
      end)
    end

    @tag driver: driver
    test "fill rejects a readonly field with #{driver}" do
      with_html(unquote(driver), ~s(<input aria-label="Name" readonly>), fn session ->
        assert_raise Fluffy.ActionabilityError, ~r/readonly/, fn ->
          fill(session, by_label("Name"), "Ada", timeout: 5)
        end
      end)
    end

    @tag driver: driver
    test "readonly does not hide a non-fillable target error with #{driver}" do
      with_html(unquote(driver), ~s(<button readonly>Save</button>), fn session ->
        error =
          assert_raise Fluffy.ActionabilityError, ~r/not editable/, fn ->
            fill(session, by_role(:button, name: "Save"), "Ada", timeout: 5)
          end

        assert error.reason == :not_editable
      end)
    end

    @tag driver: driver
    test "editable matches enabled and readonly form state with #{driver}" do
      html = """
      <label>Writable <input></label>
      <label>Readonly <input readonly></label>
      <label>Disabled <input disabled></label>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(editable(by_label("Writable")))
        |> expect(not_(editable(by_label("Readonly"))))
        |> expect(not_(editable(by_label("Disabled"))))
      end)
    end

    @tag driver: driver
    test "enabled and disabled match native, fieldset, and ARIA state with #{driver}" do
      html = """
      <button>Enabled</button>
      <button disabled>Native disabled</button>
      <fieldset disabled><button>Fieldset disabled</button></fieldset>
      <button aria-disabled="true">ARIA disabled</button>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(enabled(by_role(:button, name: "Enabled")))
        |> expect(not_(disabled(by_role(:button, name: "Enabled"))))
        |> expect(disabled(by_role(:button, name: "Native disabled")))
        |> expect(disabled(by_role(:button, name: "Fieldset disabled")))
        |> expect(disabled(by_role(:button, name: "ARIA disabled")))
        |> expect(not_(enabled(by_role(:button, name: "ARIA disabled"))))
      end)
    end

    @tag driver: driver
    test "ARIA readonly does not replace native input readonly with #{driver}" do
      with_html(unquote(driver), ~s(<input aria-label="Name" aria-readonly="true">), fn session ->
        session
        |> fill(by_label("Name"), "Ada")
        |> expect(value(by_label("Name"), "Ada"))
      end)
    end

    @tag driver: driver
    test "fill treats an invalid input type as text with #{driver}" do
      with_html(unquote(driver), ~s(<input type="check" aria-label="Fallback">), fn session ->
        session
        |> fill(by_label("Fallback"), "updated")
        |> expect(value(by_label("Fallback"), "updated"))
      end)
    end

    for {type, value, attributes} <- @set_value_input_cases do
      @tag driver: driver
      test "fill accepts a valid #{type} value with #{driver}" do
        html =
          ~s(<input type="#{unquote(type)}" aria-label="Specialized" #{unquote(attributes)}>)

        with_html(unquote(driver), html, fn session ->
          session
          |> fill(by_label("Specialized"), unquote(value))
          |> expect(value(by_label("Specialized"), unquote(value)))
        end)
      end
    end

    @tag driver: driver
    test "a disabled fieldset disables controls outside its first legend with #{driver}" do
      html = """
      <fieldset disabled>
        <legend><label>Allowed <input value="old"></label></legend>
        <label>Blocked <input value="old"></label>
      </fieldset>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> fill(by_label("Allowed"), "new")
        |> expect(value(by_label("Allowed"), "new"))

        assert_raise Fluffy.ActionabilityError, ~r/disabled/, fn ->
          fill(session, by_label("Blocked"), "new", timeout: 5)
        end
      end)
    end

    @tag driver: driver
    test "a reset button restores current properties from form defaults with #{driver}" do
      html = """
      <form>
        <label>Name <input value="initial"></label>
        <label><input type="checkbox" checked>Enabled</label>
        <label>Notes <textarea>original</textarea></label>
        <label>Plan
          <select>
            <option value="free" selected>Free</option>
            <option value="pro">Pro</option>
          </select>
        </label>
        <button type="reset">Reset</button>
      </form>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> fill(by_label("Name"), "changed")
        |> uncheck(by_role(:checkbox, name: "Enabled"))
        |> fill(by_label("Notes"), "changed")
        |> select_option(by_label("Plan"), "pro")
        |> click(by_role(:button, name: "Reset"))
        |> expect(value(by_label("Name"), "initial"))
        |> expect(checked(by_role(:checkbox, name: "Enabled")))
        |> expect(value(by_label("Notes"), "original"))
        |> expect(value(by_label("Plan"), "free"))
      end)
    end

    @tag driver: driver
    test "reset restores the last declared radio default within its group with #{driver}" do
      first = by_role(:radio, name: "First")
      second = by_role(:radio, name: "Second")

      html = """
      <form>
        <label><input type="radio" name="choice" checked>First</label>
        <label><input type="radio" name="choice" checked>Second</label>
        <button type="reset">Reset</button>
      </form>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> check(first)
        |> expect(checked(first))
        |> click(by_role(:button, name: "Reset"))
        |> expect(not_(checked(first)))
        |> expect(checked(second))
      end)
    end
  end

  @tag driver: :playwright
  test "the browser oracle fixes fill input/change timing" do
    html = """
    <input aria-label="Name" value="old"
      onfocus="events.value += 'focus:' + this.value + '|'"
      oninput="events.value += 'input:' + this.value + '|'"
      onchange="events.value += 'change:' + this.value + '|'"
      onblur="events.value += 'blur:' + this.value + '|'">
    <input id="events" aria-label="Events" value="">
    """

    with_html(:playwright, html, fn session ->
      name = by_label("Name")
      events = by_label("Events")

      session
      |> fill(name, "new")
      |> expect(value(events, "focus:old|input:new|"))
      |> blur(name)
      |> expect(value(events, "focus:old|input:new|change:new|blur:new|"))
    end)
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
