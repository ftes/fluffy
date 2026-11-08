defmodule Fluffy.Conformance.LivePatchActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  @upload Path.expand("../support/fixtures/fluffy-upload.txt", __DIR__)
  @second_upload Path.expand("../support/fixtures/fluffy-upload-second.txt", __DIR__)

  defp live_session(driver) do
    start_session(driver, base_url: Fluffy.TestServer.base_url(), endpoint: Fluffy.TestWeb.Endpoint)
  end

  defp url_query(session), do: URI.parse(Fluffy.Session.current_page(session).url).query

  defp visible(session, text), do: expect(session, text |> by_text(exact: true) |> to_be_visible())

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "a key press whose keydown patches still sends its keyup with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/keys")
      |> press(by_label("Keys", exact: true), "Enter")
      |> visible("Keyups: 1")
    end

    @tag driver: driver
    test "a checkbox whose click patches still sends its change with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/toggle")
      |> check(by_label("Toggle", exact: true))
      |> visible("Changes: 1")
    end

    @tag driver: driver
    test "an upload whose progress patches still submits with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/progress")
      |> set_input_files(by_label("Attachment", exact: true), @upload)
      |> click(by_role(:button, name: "Save", exact: true))
      |> visible("Saves: 1")
    end

    @tag driver: driver
    test "an auto upload still starts when its change patches with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/auto-change")
      |> set_input_files(by_label("Attachment", exact: true), @upload)
      |> visible("Uploaded: 1")
    end

    @tag driver: driver
    test "an upload whose progress inserts content before the form still submits with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/progress-insert")
      |> set_input_files(by_label("Attachment", exact: true), @upload)
      |> click(by_role(:button, name: "Save", exact: true))
      |> visible("Saves: 1")
    end

    @tag driver: driver
    test "an auto upload whose progress removes its form ends cleanly with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/auto-remove")
      |> set_input_files(by_label("Attachment", exact: true), @upload)
      |> visible("Uploaded: 1")
    end

    @tag driver: driver
    test "a key press whose keydown patches its input away finishes with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/keydown-remove")
      |> press(by_label("Keys", exact: true), "Enter")
      |> expect(Fluffy.Expect.page_to_have_url("/live/patching/keydown-remove?step=keydown"))
    end

    @tag driver: driver
    test "a last() key press keeps its keyup on its id-less input when the keydown adds a row with #{driver}", %{
      driver: driver
    } do
      driver
      |> live_session()
      |> visit("/live/patching/rows-append")
      |> press("Twin" |> by_label(exact: true) |> last(), "Enter")
      |> visible("Row keyups: b.")
    end

    @tag driver: driver
    test "a key press goes on after its keydown changes what its locator matches with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/keydown-rename")
      |> press(by_label("Keys", exact: true), "Enter")
      |> visible("Keyups: 1")
    end

    @tag driver: driver
    test "a form that hides its file input during the upload still submits with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/input-hide")
      |> set_input_files(by_label("Attachment", exact: true), @upload)
      |> click(by_role(:button, name: "Save", exact: true))
      |> visible("Saves: 1")
    end

    @tag driver: driver
    test "the remaining uploads go on after a patch inserts a form before theirs with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/progress-insert-form")
      |> set_input_files(by_label("Attachment", exact: true), [@upload, @second_upload])
      |> click(by_role(:button, name: "Save", exact: true))
      |> visible("Consumed: 2")
    end

    @tag driver: driver
    test "an upload survives a render that inserts content before its form with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/validate-insert")
      |> set_input_files(by_label("Attachment", exact: true), @upload)
      |> click(by_role(:button, name: "Save", exact: true))
      |> visible("Consumed: 1")
    end

    @tag driver: driver
    test "a key press sends no keyup once its keydown removes the binding with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/keydown-unbind")
      |> press(by_label("Keys", exact: true), "Enter")
      |> expect(Fluffy.Expect.page_to_have_url("/live/patching/keydown-unbind?step=keydown"))
    end

    @tag driver: driver
    test "an upload to a form without an id submits after a patch shifts it with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/idless-insert")
      |> set_input_files(by_label("Attachment", exact: true), @upload)
      |> click(by_role(:button, name: "Save", exact: true))
      |> visible("Saves: 1")
    end

    @tag driver: driver
    test "the remaining uploads go on after a patch shifts a form without an id with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/idless-insert")
      |> set_input_files(by_label("Attachment", exact: true), [@upload, @second_upload])
      |> click(by_role(:button, name: "Save", exact: true))
      |> visible("Consumed: 2")
    end

    @tag driver: driver
    test "a form that patches after consuming its uploads can be submitted again with #{driver}", %{driver: driver} do
      driver
      |> live_session()
      |> visit("/live/patching/submit")
      |> set_input_files(by_label("Attachment", exact: true), @upload)
      |> click(by_role(:button, name: "Save", exact: true))
      |> visible("Saves: 1")
      |> click(by_role(:button, name: "Save", exact: true))
      |> visible("Saves: 2")
    end
  end

  @tag driver: :phoenix
  test "an upload whose progress removes its form stops at the entry that did" do
    session =
      :phoenix
      |> live_session()
      |> visit("/live/patching/progress-remove")
      |> set_input_files(by_label("Attachment", exact: true), [@upload, @second_upload])
      |> click(by_role(:button, name: "Save", exact: true))

    visible(session, "Uploaded: 1")
    visible(session, "Saves: 0")
    assert url_query(session) == "step=uploaded"
  end

  # Browsers race the keyup against the keydown's patch. Chromium and WebKit send
  # it first by default, which these pin; Firefox or a press delay may not.
  @tag driver: :phoenix
  test "a key press sends its keyup after its keydown removes the target" do
    :phoenix
    |> live_session()
    |> visit("/live/patching/keydown-remove-unpatched")
    |> press(by_label("Keys", exact: true), "Enter")
    |> visible("Keyups: 1")
  end

  @tag driver: :phoenix
  test "a key press sends its keyup after its keydown removes its keyup binding" do
    :phoenix
    |> live_session()
    |> visit("/live/patching/keydown-unbind")
    |> press(by_label("Keys", exact: true), "Enter")
    |> visible("Keyups: 1")
  end

  for {pick, row} <- [first: "a", last: "b"] do
    @tag driver: :phoenix
    test "a key press keeps its keyup on its id-less input when the keydown removes the #{pick} row" do
      input = by_label("Twin", exact: true)

      :phoenix
      |> live_session()
      |> visit("/live/patching/rows-remove")
      |> press(apply(Fluffy.Locator, unquote(pick), [input]), "Enter")
      |> visible("Row keyups: #{unquote(row)}.")
    end
  end

  @tag driver: :phoenix
  test "a first() key press keeps its keyup on its id-less input when the keydown prepends a twin" do
    :phoenix
    |> live_session()
    |> visit("/live/patching/rows-prepend")
    |> press("Twin" |> by_label(exact: true) |> first(), "Enter")
    |> visible("Row keyups: a.")
  end

  @tag driver: :phoenix
  test "a key press sends its keyup to the view when its keydown removes a plain phx-target element" do
    :phoenix
    |> live_session()
    |> visit("/live/patching/plain-target")
    |> press(by_label("Plain keys", exact: true), "Enter")
    |> visible("Keyups: 1")
  end

  @tag driver: :phoenix
  test "a key press ends cleanly when its keydown makes the parent remove its nested view" do
    :phoenix
    |> live_session()
    |> visit("/live/nested")
    |> press(by_label("Remove child key", exact: true), "Enter")
    |> visible("Child removed")
  end

  # LiveViewTest destroys the component before a keyup can reach it. A browser
  # that sends the keyup before the patch still reaches it.
  for mode <- ~w(component-selector component-replaced component-myself) do
    @tag driver: :phoenix
    test "a key press ends cleanly when its keydown removes the #{mode} that handles its keyup" do
      :phoenix
      |> live_session()
      |> visit("/live/patching/#{unquote(mode)}")
      |> press(by_label("Component keys", exact: true), "Enter")
      |> visible("Component keyups: 0")
    end
  end

  @tag driver: :phoenix
  test "a key press keeps its keyup on an id-less input when a bound row is prepended" do
    :phoenix
    |> live_session()
    |> visit("/live/patching/idless-row")
    |> press(by_label("Row keys", exact: true), "Enter")
    |> visible("Keyups: 1")
    |> visible("Inserted keyups: 0")
  end

  @tag driver: :phoenix
  test "a key press keeps its keyup on an id-less input when a wrapper is prepended" do
    :phoenix
    |> live_session()
    |> visit("/live/patching/idless-wrapper")
    |> press(by_label("Row keys", exact: true), "Enter")
    |> visible("Keyups: 1")
  end

  @tag driver: :phoenix
  test "a key press keeps its keyup on an id-less input its locator stops matching" do
    :phoenix
    |> live_session()
    |> visit("/live/patching/idless-rename")
    |> press(by_label("Row keys", exact: true), "Enter")
    |> visible("Keyups: 1")
  end

  @tag driver: :phoenix
  test "a key press keeps its keyup on an id-less input its locator starts matching twice" do
    :phoenix
    |> live_session()
    |> visit("/live/patching/idless-append")
    |> press(by_label("Row keys", exact: true), "Enter")
    |> visible("Keyups: 1")
    |> visible("Inserted keyups: 0")
  end
end
