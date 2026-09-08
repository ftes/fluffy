defmodule Fluffy.Conformance.DialogEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Dialog
  alias Fluffy.Event

  @tag driver: :playwright
  test "accepts and captures a confirmation dialog" do
    session =
      playwright_session("""
      <button onclick="result.textContent = confirm('Proceed?') ? 'accepted' : 'dismissed'">
        Confirm
      </button>
      <p id="result"></p>
      """)

    session =
      session
      |> wait_for(
        Event.dialog(:confirmation, accept: true),
        &click(&1, by_role(:button, name: "Confirm"))
      )
      |> expect(dialog_type(:confirmation, :confirm))
      |> expect(dialog_message(:confirmation, "Proceed?"))
      |> expect(dialog_default_value(:confirmation, ""))
      |> expect(dialog_action(:confirmation, :accept))
      |> expect(visible(by_text("accepted")))

    assert %Dialog{type: :confirm, action: :accept} = dialog(session, :confirmation)
  end

  @tag driver: :playwright
  test "dismisses a confirmation dialog" do
    """
    <button onclick="result.textContent = confirm('Proceed?') ? 'accepted' : 'dismissed'">
      Confirm
    </button>
    <p id="result"></p>
    """
    |> playwright_session()
    |> wait_for(
      Event.dialog(:confirmation, dismiss: true),
      &click(&1, by_role(:button, name: "Confirm"))
    )
    |> expect(dialog_action(:confirmation, :dismiss))
    |> expect(visible(by_text("dismissed")))
  end

  @tag driver: :playwright
  test "answers a prompt using a dialog-dependent decision" do
    """
    <button onclick="result.textContent = prompt('Your name?', 'Anonymous')">Prompt</button>
    <p id="result"></p>
    """
    |> playwright_session()
    |> wait_for(
      Event.dialog(:name,
        decision: fn %Dialog{type: :prompt, default_value: "Anonymous"} ->
          {:accept, "Fluffy"}
        end
      ),
      &click(&1, by_role(:button, name: "Prompt"))
    )
    |> expect(dialog_type(:name, :prompt))
    |> expect(dialog_message(:name, "Your name?"))
    |> expect(dialog_default_value(:name, "Anonymous"))
    |> expect(dialog_action(:name, :accept))
    |> expect(dialog_prompt_text(:name, "Fluffy"))
    |> expect(visible(by_text("Fluffy")))
  end

  test "reports dialogs as browser-only before running a Phoenix action" do
    session = Fluffy.session_for_html(:static, "<button>Open dialog</button>")
    Process.put(:dialog_action_ran, false)

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        wait_for(session, Event.dialog(:dialog, accept: true), fn session ->
          Process.put(:dialog_action_ran, true)
          session
        end)
      end

    assert error.capability == :browser_dialogs
    refute Process.get(:dialog_action_ran)
  end

  defp playwright_session(html) do
    session =
      Fluffy.session_for_html(:playwright, html, base_url: Fluffy.TestServer.base_url())

    session
  end
end
