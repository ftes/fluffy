defmodule Fluffy.Conformance.DialogEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Dialog
  alias Fluffy.Event
  alias Fluffy.Playwright

  @tag driver: :playwright
  test "a one-shot handler asserts metadata and accepts while a separate wait requires the dialog" do
    session = session()

    session
    |> once(Event.dialog(), fn dialog ->
      assert dialog.type == :confirm
      assert dialog.message == "Proceed?"
      assert dialog.default_value == ""
      Dialog.accept(dialog)
    end)
    |> expect_event(Event.dialog(), &click(&1, by_role(:button, name: "Confirm")), fn dialog ->
      assert %Dialog{type: :confirm, message: "Proceed?"} = dialog
    end)
    |> expect("accepted" |> by_text(exact: true) |> to_be_visible())
    |> click(by_role(:button, name: "Confirm"))
    |> expect("dismissed" |> by_text(exact: true) |> to_be_visible())
  end

  @tag driver: :playwright
  test "persistent catch-all handling and explicit removal restore automatic dismissal" do
    accept = &Dialog.accept/1

    session()
    |> on(Event.dialog(), accept)
    |> click(by_role(:button, name: "Confirm"))
    |> expect("accepted" |> by_text(exact: true) |> to_be_visible())
    |> click(by_role(:button, name: "Confirm"))
    |> expect("accepted" |> by_text(exact: true) |> to_be_visible())
    |> off(Event.dialog(), accept)
    |> click(by_role(:button, name: "Confirm"))
    |> expect("dismissed" |> by_text(exact: true) |> to_be_visible())
  end

  @tag driver: :playwright
  test "dismisses a dialog explicitly" do
    session()
    |> once(Event.dialog(), &Dialog.dismiss/1)
    |> expect_event(Event.dialog(), &click(&1, by_role(:button, name: "Confirm")))
    |> expect("dismissed" |> by_text(exact: true) |> to_be_visible())
  end

  @tag driver: :playwright
  test "supplies prompt text after asserting its default value" do
    session()
    |> once(Event.dialog(), fn dialog ->
      assert dialog.type == :prompt
      assert dialog.message == "Your name?"
      assert dialog.default_value == "Anonymous"
      Dialog.accept(dialog, "Fluffy")
    end)
    |> expect_event(Event.dialog(), &click(&1, by_role(:button, name: "Prompt")))
    |> expect("Fluffy" |> by_text(exact: true) |> to_be_visible())
  end

  @tag driver: :playwright
  test "a rejected predicate leaves the dialog unresolved and a wait only observes" do
    session = session()
    handler = fn _ -> flunk("a rejected dialog must not reach the handler") end
    on(session, Event.dialog(fn _ -> false end), handler)
    pending = wait_for(session, Event.dialog())
    # Schedule outside the evaluated call so the test can inspect the unresolved dialog.
    Playwright.evaluate(session, "setTimeout(() => { window.dialogResult = confirm('Proceed?') }, 0); true")
    dialog = await(pending)
    assert Dialog.accept(dialog) == :ok
    assert Playwright.evaluate(session, "window.dialogResult") == true
    off(session, Event.dialog(), handler)
  end

  @tag driver: :playwright
  test "two observers and one handler receive the same dialog" do
    session = session()
    once(session, Event.dialog(), &Dialog.accept/1)
    first = wait_for(session, Event.dialog())
    second = wait_for(session, Event.dialog())
    click(session, by_role(:button, name: "Confirm"))
    assert await(first) == await(second)
  end

  @tag driver: :playwright
  test "dialog listeners stay bound to their original page" do
    original = session()
    handler = &Dialog.accept/1
    on(original, Event.dialog(), handler)
    other = switch_page(original, new_page(original))
    off(other, Event.dialog(), handler)
    assert Playwright.evaluate(other, "confirm('Other')") == false
    original |> click(by_role(:button, name: "Confirm")) |> expect("accepted" |> by_text(exact: true) |> to_be_visible())
    off(original, Event.dialog(), handler)
  end

  test "reports dialogs as browser-only before invoking an action" do
    session = session_for_html(:static, "<button>Open dialog</button>")

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        expect_event(session, Event.dialog(), fn _ -> flunk("unsupported action ran") end)
      end

    assert error.capability == :browser_dialogs
  end

  defp session do
    session_for_html(
      :playwright,
      """
      <button onclick="result.textContent = confirm('Proceed?') ? 'accepted' : 'dismissed'">Confirm</button>
      <button onclick="result.textContent = prompt('Your name?', 'Anonymous')">Prompt</button>
      <p id="result"></p>
      """,
      base_url: Fluffy.TestServer.base_url()
    )
  end
end
