defmodule Fluffy.Conformance.ElementStateTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # Playwright's element states (getAriaDisabled, getReadonly and getChecked in
  # roleUtils.ts), which Phoenix ports. The cases follow upstream's
  # selectors-role.spec.ts, expect-boolean.spec.ts and locator-convenience.spec.ts.
  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "disabled follows native, optgroup, fieldset and ARIA state with #{driver}" do
      html = """
      <button data-testid="plain">Lumos</button>
      <button data-testid="native" disabled="yes">Nox</button>
      <button data-testid="aria" aria-disabled="TRUE">Alohomora</button>
      <button data-testid="aria-false" aria-disabled="false">Accio</button>
      <div data-testid="div" disabled>Pensieve</div>
      <div data-testid="role-button" role="button" aria-disabled="true">Portkey</div>
      <select aria-label="Spells">
        <optgroup disabled><option data-testid="grouped">Expelliarmus</option></optgroup>
        <optgroup><option data-testid="open">Stupefy</option></optgroup>
        <option data-testid="option" disabled>Riddikulus</option>
        <option data-testid="aria-option" aria-disabled="true">Obliviate</option>
      </select>
      """

      with_html(unquote(driver), html, fn session ->
        for id <- ~w(native aria role-button grouped option aria-option) do
          expect(session, id |> by_test_id() |> to_be_disabled())
        end

        for id <- ~w(plain aria-false div open) do
          expect(session, id |> by_test_id() |> to_be_enabled())
        end
      end)
    end

    @tag driver: driver
    test "aria-disabled applies to descendants with a role that takes it with #{driver}" do
      html = """
      <span aria-disabled="true">
        <button data-testid="inherited">Open the Chamber</button>
        <h1 data-testid="heading">Hogwarts</h1>
        <div aria-disabled="false"><button data-testid="reenabled">Reparo</button></div>
      </span>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect("inherited" |> by_test_id() |> to_be_disabled())
        |> expect("heading" |> by_test_id() |> to_be_enabled())
        |> expect("reenabled" |> by_test_id() |> to_be_enabled())
      end)
    end

    @tag driver: driver
    test "a disabled fieldset spares its first legend with #{driver}" do
      html = """
      <fieldset disabled>
        <input aria-label="Inside">
        <legend><button data-testid="inside-legend">Deathly Hallows</button></legend>
      </fieldset>
      <fieldset disabled>
        <legend><div><button data-testid="nested-in-legend">Elder Wand</button></div></legend>
      </fieldset>
      <fieldset disabled>
        <div></div>
        <legend><button data-testid="first-legend">Resurrection Stone</button></legend>
        <legend><button data-testid="second-legend">Invisibility Cloak</button></legend>
      </fieldset>
      <fieldset disabled>
        <fieldset><button data-testid="deep">Horcrux</button></fieldset>
      </fieldset>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect("Inside" |> by_label() |> to_be_disabled())
        |> expect("inside-legend" |> by_test_id() |> to_be_enabled())
        |> expect("nested-in-legend" |> by_test_id() |> to_be_enabled())
        |> expect("first-legend" |> by_test_id() |> to_be_enabled())
        |> expect("second-legend" |> by_test_id() |> to_be_disabled())
        |> expect("deep" |> by_test_id() |> to_be_disabled())
      end)
    end

    @tag driver: driver
    test "fill and select_option reject an inherited or option aria-disabled with #{driver}" do
      html = """
      <div aria-disabled="true"><input aria-label="Name"></div>
      <select aria-label="Broomstick"><option>Cleansweep</option><option aria-disabled="true">Firebolt</option></select>
      """

      with_html(unquote(driver), html, fn session ->
        assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled/, fn ->
          fill(session, by_label("Name"), "Hermione", timeout: 5)
        end)

        assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled option/, fn ->
          select_option(session, by_label("Broomstick"), "Firebolt", timeout: 5)
        end)
      end)
    end

    @tag driver: driver
    test "editable follows native readonly, aria-readonly and contenteditable with #{driver}" do
      html = """
      <input data-testid="input">
      <input data-testid="disabled" disabled>
      <textarea data-testid="textarea" readonly></textarea>
      <select data-testid="select" readonly><option>One</option></select>
      <input data-testid="checkbox" type="checkbox">
      <input data-testid="aria-input" aria-readonly="true">
      <div data-testid="editable" contenteditable="true"></div>
      <div contenteditable><span data-testid="inherited">Inherited</span><p data-testid="off" contenteditable="false">Off</p></div>
      <span data-testid="readonly-textbox" role="textbox" aria-readonly="true"></span>
      <span data-testid="textbox" role="textbox"></span>
      """

      with_html(unquote(driver), html, fn session ->
        for id <- ~w(input checkbox aria-input editable inherited textbox) do
          expect(session, id |> by_test_id() |> to_be_editable())
        end

        for id <- ~w(disabled textarea select readonly-textbox) do
          expect(session, id |> by_test_id() |> to_be_editable(editable: false))
        end
      end)
    end

    @tag driver: driver
    test "editable raises for an element without a readonly state with #{driver}" do
      with_html(unquote(driver), ~s(<button>Accio</button><p contenteditable="false">Off</p>), fn session ->
        for locator <- [by_role(:button), by_text("Off")] do
          error = assert_raise ExUnit.AssertionError, fn -> expect(session, to_be_editable(locator)) end

          assert error.message =~
                   "Error: Element is not an <input>, <textarea>, <select> or [contenteditable] and does not " <>
                     "have a role allowing [aria-readonly]"
        end
      end)
    end

    @tag driver: driver
    test "checked follows native checkedness and aria-checked with #{driver}" do
      roles = ~w(checkbox menuitemcheckbox option radio switch menuitemradio treeitem)

      html = """
      <input data-testid="native" type="checkbox" checked>
      <input data-testid="native-radio" type="radio">
      #{Enum.map_join(roles, "\n", &~s(<div data-testid="#{&1}" role="#{&1}" aria-checked="TRUE">#{&1}</div>))}
      <div data-testid="mixed" role="checkbox" aria-checked="mixed">Mixed</div>
      <div data-testid="unset" role="switch">Unset</div>
      <div role="checkbox" aria-checked="true"><span data-testid="inside">Inside</span></div>
      """

      with_html(unquote(driver), html, fn session ->
        for id <- ["native", "inside" | roles] do
          expect(session, id |> by_test_id() |> to_be_checked())
        end

        for id <- ~w(native-radio mixed unset) do
          expect(session, id |> by_test_id() |> to_be_checked(checked: false))
        end
      end)
    end

    @tag driver: driver
    test "checked and editable follow a label to its control with #{driver}" do
      html = """
      <label><input type="checkbox" checked> Join Dumbledore's Army</label>
      <label for="password">Password to the common room</label><input id="password" readonly>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect("Join Dumbledore's Army" |> by_text() |> to_be_checked())
        |> expect("Password to the common room" |> by_text() |> to_be_editable(editable: false))
      end)
    end

    @tag driver: driver
    test "checked raises for an element that is not a checkbox or radio with #{driver}" do
      with_html(unquote(driver), ~s(<div role="button" aria-checked="true">Not a checkbox</div>), fn session ->
        for expectation <- [to_be_checked(by_role(:button)), not_(to_be_checked(by_role(:button)))] do
          error = assert_raise ExUnit.AssertionError, fn -> expect(session, expectation) end
          assert error.message =~ ~r/\AExpected (not )?by_role\(:button\) to be checked\n/
          assert error.message =~ "Error: Not a checkbox or radio button"
        end
      end)
    end
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.Support.Server.base_url())
    fun.(session)
  end
end
