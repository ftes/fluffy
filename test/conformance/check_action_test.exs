defmodule Fluffy.Conformance.CheckActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Playwright

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "check and uncheck are idempotent for checkboxes with #{driver}" do
      checkbox = by_role(:checkbox, name: "Updates")

      html =
        ~s(<label for="updates">Updates</label><input id="updates" type="checkbox" checked>)

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(checked(checkbox, checked: true))
        |> check(checkbox)
        |> expect(checked(checkbox))
        |> uncheck(checkbox)
        |> expect(checked(checkbox, checked: false))
        |> uncheck(checkbox)
        |> expect(not_(checked(checkbox)))
        |> check(checkbox)
        |> expect(checked(checkbox))
      end)
    end

    @tag driver: driver
    test "checking a radio unchecks its named group peer with #{driver}" do
      email = by_role(:radio, name: "Email")
      sms = by_role(:radio, name: "SMS")

      html = """
      <label><input type="radio" name="contact" value="email" checked>Email</label>
      <label><input type="radio" name="contact" value="sms">SMS</label>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(checked(email))
        |> expect(not_(checked(sms)))
        |> check(sms)
        |> expect(not_(checked(email)))
        |> expect(checked(sms))
        |> check(sms)
        |> expect(checked(sms))
      end)
    end

    @tag driver: driver
    test "same-named radios with different form owners are separate groups with #{driver}" do
      first = by_role(:radio, name: "First email")
      second = by_role(:radio, name: "Second SMS")

      html = """
      <form id="first-form">
        <label><input type="radio" name="contact" value="email" checked>First email</label>
        <label><input type="radio" name="contact" value="sms">First SMS</label>
      </form>
      <form id="second-form">
        <label><input type="radio" name="contact" value="email" checked>Second email</label>
        <label><input type="radio" name="contact" value="sms">Second SMS</label>
      </form>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> check(second)
        |> expect(checked(first))
        |> expect(checked(second))
      end)
    end

    @tag driver: driver
    test "the last initially checked radio wins within a group with #{driver}" do
      html = """
      <label><input type="radio" name="contact" checked>Email</label>
      <label><input type="radio" name="contact" checked>SMS</label>
      """

      with_html(unquote(driver), html, fn session ->
        session
        |> expect(not_(checked(by_role(:radio, name: "Email"))))
        |> expect(checked(by_role(:radio, name: "SMS")))
      end)
    end

    @tag driver: driver
    test "a selected radio cannot be directly unchecked with #{driver}" do
      html = ~s(<label><input type="radio" name="contact" checked>Email</label>)

      with_html(unquote(driver), html, fn session ->
        assert_raise Fluffy.ActionabilityError, ~r/cannot uncheck a selected radio/, fn ->
          uncheck(session, by_role(:radio, name: "Email"), timeout: 5)
        end
      end)
    end

    @tag driver: driver
    test "changing a disabled checkbox is rejected with #{driver}" do
      html = ~s(<label><input type="checkbox" disabled>Updates</label>)

      with_html(unquote(driver), html, fn session ->
        assert_raise Fluffy.ActionabilityError, ~r/disabled/, fn ->
          check(session, by_role(:checkbox, name: "Updates"), timeout: 5)
        end
      end)
    end
  end

  test "Playwright can assert a browser-owned indeterminate checkbox state" do
    checkbox = by_role(:checkbox, name: "Construction")
    html = ~s(<label><input id="construction" type="checkbox">Construction</label>)

    with_html(:playwright, html, fn session ->
      session
      |> tap(fn session ->
        Playwright.evaluate(
          session,
          "document.querySelector('#construction').indeterminate = true"
        )
      end)
      |> expect(checked(checkbox, indeterminate: true))
    end)
  end

  test "the Static driver rejects browser-owned indeterminate checkbox state" do
    checkbox = by_role(:checkbox, name: "Construction")
    html = ~s(<label><input type="checkbox">Construction</label>)

    with_html(:static, html, fn session ->
      assert_raise Fluffy.CapabilityError, ~r/browser-owned DOM property/, fn ->
        expect(session, checked(checkbox, indeterminate: true))
      end
    end)
  end

  test "checked options reject Playwright's conflicting state request" do
    assert_raise ArgumentError, ~r/cannot be used together/, fn ->
      checked(by_role(:checkbox), checked: false, indeterminate: true)
    end
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
