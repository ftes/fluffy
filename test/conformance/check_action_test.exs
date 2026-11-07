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
        |> expect(to_be_checked(checkbox, checked: true))
        |> check(checkbox)
        |> expect(to_be_checked(checkbox))
        |> uncheck(checkbox)
        |> expect(to_be_checked(checkbox, checked: false))
        |> uncheck(checkbox)
        |> expect(not_(to_be_checked(checkbox)))
        |> check(checkbox)
        |> expect(to_be_checked(checkbox))
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
        |> expect(to_be_checked(email))
        |> expect(not_(to_be_checked(sms)))
        |> check(sms)
        |> expect(not_(to_be_checked(email)))
        |> expect(to_be_checked(sms))
        |> check(sms)
        |> expect(to_be_checked(sms))
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
        |> expect(to_be_checked(first))
        |> expect(to_be_checked(second))
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
        |> expect(:radio |> by_role(name: "Email") |> to_be_checked() |> not_())
        |> expect(:radio |> by_role(name: "SMS") |> to_be_checked())
      end)
    end

    @tag driver: driver
    test "a selected radio cannot be directly unchecked with #{driver}" do
      html = ~s(<label><input type="radio" name="contact" checked>Email</label>)

      with_html(unquote(driver), html, fn session ->
        assert_action_error(session, Fluffy.ActionabilityError, ~r/cannot uncheck a selected radio/, fn ->
          uncheck(session, by_role(:radio, name: "Email"), timeout: 5)
        end)
      end)
    end

    @tag driver: driver
    test "changing a disabled checkbox is rejected with #{driver}" do
      html = ~s(<label><input type="checkbox" disabled>Updates</label>)

      with_html(unquote(driver), html, fn session ->
        assert_action_error(session, Fluffy.ActionabilityError, ~r/disabled/, fn ->
          check(session, by_role(:checkbox, name: "Updates"), timeout: 5)
        end)
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
      |> expect(to_be_checked(checkbox, indeterminate: true))
    end)
  end

  # Page code here reverts the click at once; a LiveView patch does the same a
  # round trip later, often before Playwright reads the state back.
  test "Playwright check and uncheck succeed when page code reverts the click" do
    revert = ~s|oninput="queueMicrotask(() => this.checked = !this.checked)"|

    html = """
    <label><input type="checkbox" #{revert}>Updates</label>
    <label><input type="checkbox" checked #{revert}>Digest</label>
    """

    with_html(:playwright, html, fn session ->
      session
      |> check(by_role(:checkbox, name: "Updates"))
      |> expect(to_be_checked(by_role(:checkbox, name: "Updates"), checked: false))
      |> uncheck(by_role(:checkbox, name: "Digest"))
      |> expect(to_be_checked(by_role(:checkbox, name: "Digest")))
    end)
  end

  test "Playwright check and uncheck succeed when page code in an iframe reverts the click" do
    revert = ~s|oninput="queueMicrotask(() => this.checked = !this.checked)"|

    inner = """
    <label><input type="checkbox" #{revert}>Updates</label>
    <label><input type="checkbox" checked #{revert}>Digest</label>
    """

    frame = frame_locator("iframe")

    with_html(:playwright, ~s(<iframe srcdoc="#{String.replace(inner, "\"", "&quot;")}"></iframe>), fn session ->
      session
      |> check(by_role(frame, :checkbox, name: "Updates"))
      |> expect(to_be_checked(by_role(frame, :checkbox, name: "Updates"), checked: false))
      |> uncheck(by_role(frame, :checkbox, name: "Digest"))
      |> expect(to_be_checked(by_role(frame, :checkbox, name: "Digest")))
    end)
  end

  test "Playwright check fails when the click does not change the state" do
    html = ~s|<label><input type="checkbox" onclick="event.preventDefault()">Updates</label>|

    with_html(:playwright, html, fn session ->
      assert_raise Fluffy.OperationError, ~r/Clicking the checkbox did not change its state/, fn ->
        check(session, by_role(:checkbox, name: "Updates"))
      end
    end)
  end

  test "Playwright check and uncheck succeed when page code in a shadow root reverts the click" do
    shadow = """
    () => {
      const root = document.querySelector('#host').attachShadow({mode: 'open'})
      root.innerHTML = '<label><input type="checkbox">Updates</label><label><input type="checkbox" checked>Digest</label>'
      for (const input of root.querySelectorAll('input'))
        input.addEventListener('input', () => queueMicrotask(() => input.checked = !input.checked))
    }
    """

    with_html(:playwright, ~s(<div id="host"></div>), fn session ->
      Playwright.evaluate(session, shadow)

      session
      |> check(by_role(:checkbox, name: "Updates"))
      |> expect(to_be_checked(by_role(:checkbox, name: "Updates"), checked: false))
      |> uncheck(by_role(:checkbox, name: "Digest"))
      |> expect(to_be_checked(by_role(:checkbox, name: "Digest")))
    end)
  end

  test "the Static driver rejects browser-owned indeterminate checkbox state" do
    checkbox = by_role(:checkbox, name: "Construction")
    html = ~s(<label><input type="checkbox">Construction</label>)

    with_html(:static, html, fn session ->
      assert_raise Fluffy.CapabilityError, ~r/browser-owned DOM property/, fn ->
        expect(session, to_be_checked(checkbox, indeterminate: true))
      end
    end)
  end

  test "checked options reject Playwright's conflicting state request" do
    assert_raise ArgumentError, ~r/cannot be used together/, fn ->
      :checkbox |> by_role() |> to_be_checked(checked: false, indeterminate: true)
    end
  end

  defp with_html(driver, html, fun) do
    session = session_for_html(driver, html, base_url: Fluffy.TestServer.base_url())
    fun.(session)
  end
end
