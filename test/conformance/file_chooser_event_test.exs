defmodule Fluffy.Conformance.FileChooserEventTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Event
  alias Fluffy.FileChooser
  alias Fluffy.FilePayload
  alias Fluffy.Playwright

  @tag driver: :playwright
  test "captures a scripted chooser before the click and selects an in-memory file through it" do
    session = playwright_session()

    pending = wait_for(session, Event.file_chooser())
    click(session, by_role(:button, name: "Choose attachment"))
    chooser = await(pending)
    set_input_files(session, chooser, %FilePayload{name: "chosen.txt", bytes: "chosen", content_type: "text/plain"})
    refute FileChooser.multiple?(chooser)

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
  test "preserves native multiple-file rejection without mutating a single-file chooser" do
    session = playwright_session()
    pending = wait_for(session, Event.file_chooser())
    click(session, by_role(:button, name: "Choose attachment"))
    chooser = await(pending)

    error =
      assert_raise Fluffy.OperationError, fn ->
        set_input_files(session, chooser, [
          %FilePayload{name: "first.txt", bytes: "first"},
          %FilePayload{name: "second.txt", bytes: "second"}
        ])
      end

    assert error.operation == :set_input_files
    assert error.locator == chooser
    assert error.cause

    assert Playwright.evaluate(
             session,
             "document.querySelector('#attachment').files.length"
           ) == 0
  end

  @tag driver: :playwright
  test "reports and fills a multiple-file chooser in selection order" do
    session = playwright_session(multiple?: true)
    pending = wait_for(session, Event.file_chooser())
    click(session, by_role(:button, name: "Choose attachment"))
    chooser = await(pending)
    assert FileChooser.multiple?(chooser)

    session =
      set_input_files(session, chooser, [
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

    for selection <- [%FilePayload{name: "first.txt", bytes: "first"}, []] do
      pending = wait_for(session, Event.file_chooser())
      click(session, by_role(:button, name: "Choose attachment"))
      set_input_files(session, await(pending), selection)
    end

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
        expect_event(session, Event.file_chooser(), fn session ->
          Process.put(:chooser_action_ran, true)
          session
        end)
      end

    assert error.capability == :file_chooser_events
    refute Process.get(:chooser_action_ran)
  end

  @tag driver: :playwright
  test "a chooser targets its original page while preserving the selected page" do
    original = playwright_session()
    pending = wait_for(original, Event.file_chooser())
    click(original, by_role(:button, name: "Choose attachment"))
    chooser = await(pending)
    other = new_page(original, :other)
    assert set_input_files(other, chooser, %FilePayload{name: "original.txt", bytes: "original"}) == other
    assert Playwright.evaluate(original, "document.querySelector('#attachment').files[0].name") == "original.txt"
  end

  for navigation <- [:patch, :document] do
    @tag driver: :playwright
    test "chooser reconciles #{navigation} navigation before restoring page selection" do
      original = playwright_session()
      destination = if unquote(navigation) == :patch, do: "#selected", else: "/chamber"

      Playwright.evaluate(
        original,
        "destination => { document.querySelector('#attachment').onchange = () => { location.href = destination } }",
        arg: destination,
        is_function: true
      )

      pending = wait_for(original, Event.file_chooser())
      click(original, by_role(:button, name: "Choose attachment"))
      chooser = await(pending)
      other = new_page(original, :other)

      assert set_input_files(other, chooser, %FilePayload{name: "selected.txt", bytes: "selected"}) == other
      assert Fluffy.Page.url(current_page(other)) == "about:blank"

      expect(
        original,
        page_to_have_url(if(unquote(navigation) == :patch, do: [fragment: "selected"], else: [path: "/chamber"]))
      )
    end
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
