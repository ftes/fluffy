defmodule Fluffy.Conformance.ElementStateTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  # Playwright's element states (getAriaDisabled in roleUtils.ts), which Phoenix
  # ports. The cases follow upstream's selectors-role.spec.ts and expect-boolean.spec.ts.
  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "disabled follows native, optgroup, fieldset and ARIA state with #{driver}" do
      html = """
      <button data-testid="plain">Hi</button>
      <button data-testid="native" disabled="yes">Bye</button>
      <button data-testid="aria" aria-disabled="TRUE">Hello</button>
      <button data-testid="aria-false" aria-disabled="false">Oh</button>
      <div data-testid="div" disabled>Div</div>
      <div data-testid="role-button" role="button" aria-disabled="true">Role</div>
      <select aria-label="Spells">
        <optgroup disabled><option data-testid="grouped">one</option></optgroup>
        <optgroup><option data-testid="open">two</option></optgroup>
        <option data-testid="option" disabled>three</option>
        <option data-testid="aria-option" aria-disabled="true">four</option>
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
        <button data-testid="inherited">Click me</button>
        <h1 data-testid="heading">Heading</h1>
        <div aria-disabled="false"><button data-testid="reenabled">Again</button></div>
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
        <legend><button data-testid="inside-legend">legend</button></legend>
      </fieldset>
      <fieldset disabled>
        <legend><div><button data-testid="nested-in-legend">x</button></div></legend>
      </fieldset>
      <fieldset disabled>
        <div></div>
        <legend><button data-testid="first-legend">x</button></legend>
        <legend><button data-testid="second-legend">x</button></legend>
      </fieldset>
      <fieldset disabled>
        <fieldset><button data-testid="deep">x</button></fieldset>
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
      <select aria-label="Plan"><option>Free</option><option aria-disabled="true">Pro</option></select>
      """

      with_html(unquote(driver), html, fn session ->
        assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled/, fn ->
          fill(session, by_label("Name"), "Hermione", timeout: 5)
        end)

        assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled option/, fn ->
          select_option(session, by_label("Plan"), "Pro", timeout: 5)
        end)
      end)
    end
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
