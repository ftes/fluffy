defmodule Fluffy.Conformance.FillActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  @set_value_input_cases [
    {"color", "#123456", ""},
    {"date", "2025-01-02", ""},
    {"datetime-local", "2025-01-02T03:04", ""},
    {"month", "2025-01", ""},
    {"range", "7", ~s(min="0" max="10")},
    {"time", "03:04", ""},
    {"week", "2025-W01", ""}
  ]

  for attribute <- ["contenteditable", ~s(contenteditable="true"), ~s(contenteditable="plaintext-only")] do
    @tag driver: :playwright
    test "Playwright fills #{attribute} as text" do
      editor = by_role(:textbox, name: "Editor")
      html = ~s(<div role="textbox" aria-label="Editor" #{unquote(attribute)}>Initial</div>)

      with_html(:playwright, html, fn session ->
        session
        |> fill(editor, "Updated")
        |> expect(to_be_visible(by_text(editor, "Updated", exact: true)))
      end)
    end

    test "Static rejects filling #{attribute}" do
      editor = by_role(:textbox, name: "Editor")
      html = ~s(<div role="textbox" aria-label="Editor" #{unquote(attribute)}>Initial</div>)
      session = session_for_html(:static, html)

      error = assert_raise Fluffy.CapabilityError, fn -> fill(session, editor, "Updated") end
      assert error.capability == :contenteditable_fill
      assert error.driver == :static
      expect(session, to_be_visible(by_text(editor, "Initial", exact: true)))
    end
  end

  test "LiveView rejects filling contenteditable" do
    session = :phoenix |> start_session() |> visit("/live/mystic-creatures")
    editor = by_role(:textbox, name: "Editor")

    error = assert_raise Fluffy.CapabilityError, fn -> fill(session, editor, "Updated") end
    assert error.capability == :contenteditable_fill
    assert error.driver == :live
    expect(session, to_be_visible(by_text(editor, "Initial", exact: true)))
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "fill converts String.Chars values without escaping with #{driver}" do
      session = session_for_html(unquote(driver), ~s(<input aria-label="Value"><textarea aria-label="Notes"></textarea>))

      values = [
        {42, "42"},
        {12.5, "12.5"},
        {true, "true"},
        {:ready, "ready"},
        {nil, ""},
        {~D[2026-09-30], "2026-09-30"},
        {~T[12:34:56], "12:34:56"},
        {~N[2026-09-30 12:34:56], "2026-09-30 12:34:56"},
        {~U[2026-09-30 12:34:56Z], "2026-09-30 12:34:56Z"},
        {~c"<tag>&\"'", "<tag>&\"'"},
        {"<tag>&\"'", "<tag>&\"'"},
        {%Fluffy.TestFormValue{value: "<tag>&"}, "custom:<tag>&"}
      ]

      Enum.reduce(values, session, fn {value, expected}, session ->
        session
        |> fill(by_label("Value"), value)
        |> expect(to_have_value(by_label("Value"), expected))
        |> fill(by_label("Notes"), value)
        |> expect(to_have_value(by_label("Notes"), expected))
      end)

      assert_raise Protocol.UndefinedError, fn -> fill(session, by_label("Value"), %{}) end
    end

    @tag driver: driver
    test "fill replaces an input's current value with #{driver}" do
      field = by_label("Email")
      html = ~s(<label for="email">Email</label><input id="email" value="old@example.com">)

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(to_have_value(field, "old@example.com"))
        |> fill(field, "new@example.com")
        |> expect(to_have_value(field, "new@example.com"))
      end)
    end

    @tag driver: driver
    test "fill accepts an empty textarea value with #{driver}" do
      field = by_label("Notes")
      html = ~s(<label for="notes">Notes</label><textarea id="notes">Initial notes</textarea>)

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(to_have_value(field, "Initial notes"))
        |> fill(field, "")
        |> expect(to_have_value(field, ""))
      end)
    end

    @tag driver: driver
    test "fill requires exactly one target with #{driver}" do
      with_html(unquote(driver), ~s(<input title="Name"><input title="Name">), fn session ->
        assert_action_error(session, Fluffy.StrictnessError, ~r/it matched 2/, fn ->
          fill(session, by_title("Name"), "Ada", timeout: 5)
        end)
      end)
    end

    @tag driver: driver
    test "fill rejects a disabled field with #{driver}" do
      with_html(unquote(driver), ~s(<input aria-label="Name" disabled>), fn session ->
        assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled/, fn ->
          fill(session, by_label("Name"), "Ada", timeout: 5)
        end)
      end)
    end

    @tag driver: driver
    test "fill rejects a readonly field with #{driver}" do
      with_html(unquote(driver), ~s(<input aria-label="Name" readonly>), fn session ->
        assert_action_error(session, Fluffy.ActionabilityError, ~r/readonly/, fn ->
          fill(session, by_label("Name"), "Ada", timeout: 5)
        end)
      end)
    end

    @tag driver: driver
    test "readonly does not hide a non-fillable target error with #{driver}" do
      with_html(unquote(driver), ~s(<button readonly>Save</button>), fn session ->
        error =
          assert_action_error(session, Fluffy.ActionabilityError, ~r/not editable/, fn ->
            fill(session, by_role(:button, name: "Save"), "Ada", timeout: 5)
          end)

        if Fluffy.Session.current_driver(session) != :playwright, do: assert(error.cause.reason == :not_editable)
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
        |> expect("Writable" |> by_label() |> to_be_editable())
        |> expect("Readonly" |> by_label() |> to_be_editable() |> not_())
        |> expect("Disabled" |> by_label() |> to_be_editable() |> not_())
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
        |> expect(:button |> by_role(name: "Enabled") |> to_be_enabled())
        |> expect(:button |> by_role(name: "Enabled") |> to_be_disabled() |> not_())
        |> expect(:button |> by_role(name: "Native disabled") |> to_be_disabled())
        |> expect(:button |> by_role(name: "Fieldset disabled") |> to_be_disabled())
        |> expect(:button |> by_role(name: "ARIA disabled") |> to_be_disabled())
        |> expect(:button |> by_role(name: "ARIA disabled") |> to_be_enabled() |> not_())
      end)
    end

    @tag driver: driver
    test "ARIA readonly does not replace native input readonly with #{driver}" do
      with_html(unquote(driver), ~s(<input aria-label="Name" aria-readonly="true">), fn session ->
        session
        |> fill(by_label("Name"), "Ada")
        |> expect("Name" |> by_label() |> to_have_value("Ada"))
      end)
    end

    @tag driver: driver
    test "fill treats an invalid input type as text with #{driver}" do
      with_html(unquote(driver), ~s(<input type="check" aria-label="Fallback">), fn session ->
        session
        |> fill(by_label("Fallback"), "updated")
        |> expect("Fallback" |> by_label() |> to_have_value("updated"))
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
          |> expect("Specialized" |> by_label() |> to_have_value(unquote(value)))
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
        |> expect("Allowed" |> by_label() |> to_have_value("new"))

        assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled/, fn ->
          fill(session, by_label("Blocked"), "new", timeout: 5)
        end)
      end)
    end

    @tag driver: driver
    test "only Playwright resets current properties from form defaults with #{driver}" do
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
        |> expect(
          "Name"
          |> by_label()
          |> to_have_value(if(unquote(driver) == :playwright, do: "initial", else: "changed"))
        )
        |> expect(:checkbox |> by_role(name: "Enabled") |> to_be_checked(checked: unquote(driver) == :playwright))
        |> expect(
          "Notes"
          |> by_label()
          |> to_have_value(if(unquote(driver) == :playwright, do: "original", else: "changed"))
        )
        |> expect("Plan" |> by_label() |> to_have_value(if(unquote(driver) == :playwright, do: "free", else: "pro")))
      end)
    end

    @tag driver: driver
    test "only Playwright restores radio defaults on reset with #{driver}" do
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
        |> expect(to_be_checked(first))
        |> click(by_role(:button, name: "Reset"))
        |> expect(to_be_checked(first, checked: unquote(driver) != :playwright))
        |> expect(to_be_checked(second, checked: unquote(driver) == :playwright))
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
      |> expect(to_have_value(events, "focus:old|input:new|"))
      |> blur(name)
      |> expect(to_have_value(events, "focus:old|input:new|change:new|blur:new|"))
    end)
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
