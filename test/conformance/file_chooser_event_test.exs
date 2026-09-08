defmodule Fluffy.Conformance.FileChooserEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.FileChooser
  alias Fluffy.FilePayload
  alias Fluffy.Playwright

  @tag driver: :playwright
  test "captures a scripted chooser before the click and selects an in-memory file through it" do
    session = playwright_session()

    session =
      session
      |> wait_for(
        Event.file_chooser(:attachment),
        &click(&1, by_role(:button, name: "Choose attachment"))
      )
      |> set_input_files(
        :attachment,
        %FilePayload{name: "chosen.txt", bytes: "chosen", content_type: "text/plain"}
      )

    refute session |> file_chooser(:attachment) |> FileChooser.multiple?()

    assert %{"contents" => "chosen", "name" => "chosen.txt", "type" => "text/plain"} =
             Playwright.evaluate(
               session,
               """
               async () => {
                 const file = document.querySelector('#attachment').files[0];
                 return {name: file.name, type: file.type, contents: await file.text()};
               }
               """,
               is_function: true
             )
  end

  @tag driver: :playwright
  test "normalizes multiple-file rejection without mutating a single-file chooser" do
    session =
      wait_for(
        playwright_session(),
        Event.file_chooser(:attachment),
        &click(&1, by_role(:button, name: "Choose attachment"))
      )

    error =
      assert_raise Fluffy.ActionabilityError, fn ->
        set_input_files(session, :attachment, [
          %FilePayload{name: "first.txt", bytes: "first"},
          %FilePayload{name: "second.txt", bytes: "second"}
        ])
      end

    assert error.action == :set_input_files
    assert error.reason == :multiple_files_not_allowed

    assert Playwright.evaluate(
             session,
             "document.querySelector('#attachment').files.length"
           ) == 0
  end

  @tag driver: :playwright
  test "reports and fills a multiple-file chooser in selection order" do
    session =
      [multiple?: true]
      |> playwright_session()
      |> wait_for(
        Event.file_chooser(:attachments),
        &click(&1, by_role(:button, name: "Choose attachment"))
      )

    assert session |> file_chooser(:attachments) |> FileChooser.multiple?()

    session =
      set_input_files(session, :attachments, [
        %FilePayload{name: "first.txt", bytes: "first"},
        %FilePayload{name: "second.txt", bytes: "second"}
      ])

    assert Playwright.evaluate(
             session,
             "Array.from(document.querySelector('#attachment').files, file => file.name)"
           ) == ["first.txt", "second.txt"]
  end

  @tag driver: :playwright
  test "releases each chooser subscription and can capture another chooser" do
    session = playwright_session()

    session =
      session
      |> wait_for(
        Event.file_chooser(:first),
        &click(&1, by_role(:button, name: "Choose attachment"))
      )
      |> set_input_files(:first, %FilePayload{name: "first.txt", bytes: "first"})
      |> wait_for(
        Event.file_chooser(:second),
        &click(&1, by_role(:button, name: "Choose attachment"))
      )
      |> set_input_files(:second, [])

    assert Playwright.evaluate(
             session,
             "document.querySelector('#attachment').files.length"
           ) ==
             0
  end

  test "reports chooser events as browser-only before running a Phoenix action" do
    session =
      session_for_html(
        :static,
        ~s(<input id="attachment" type="file"><button>Choose attachment</button>)
      )

    Process.put(:chooser_action_ran, false)

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        wait_for(session, Event.file_chooser(:attachment), fn session ->
          Process.put(:chooser_action_ran, true)
          session
        end)
      end

    assert error.capability == :file_chooser_events
    refute Process.get(:chooser_action_ran)
  end

  defp playwright_session(options \\ []) do
    multiple = if Keyword.get(options, :multiple?, false), do: " multiple", else: ""

    session_for_html(
      :playwright,
      """
      <input id="attachment" type="file"#{multiple} hidden>
      <button onclick="document.querySelector('#attachment').click()">Choose attachment</button>
      """,
      base_url: Fluffy.TestServer.base_url()
    )
  end
end
