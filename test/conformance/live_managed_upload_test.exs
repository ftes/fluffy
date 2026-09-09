defmodule Fluffy.Conformance.LiveManagedUploadTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Driver.Live.UploadState
  alias Fluffy.FilePayload
  alias Fluffy.Session
  alias Fluffy.TestScope

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "uploads, progresses, and consumes one local file with #{driver}" do
      file = fixture_path()

      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), file)
      |> expect("Validated: true" |> by_text() |> to_be_visible())
      |> expect("Progress: 0" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Progress: 100" |> by_text() |> to_be_visible())
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
    end

    test "uploads and consumes one in-memory payload with #{driver}" do
      payload = %FilePayload{
        name: "generated.txt",
        bytes: "Generated in memory.",
        content_type: "text/plain"
      }

      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), payload)
      |> expect("Validated: true" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Consumed: generated.txt / Generated in memory." |> by_text() |> to_be_visible())
    end

    test "preserves a clicked submitter through a managed upload with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> click(by_role(:button, name: "Draft"))
      |> expect("Submitted action: draft" |> by_text() |> to_be_visible())
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
    end

    test "follows an ordinary link from a form with a tracked upload with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> click(by_role(:link, name: "Leave upload form"))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=upload-link"))
    end

    test "follows a Live redirect after a managed upload submit with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/redirect")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> click(by_role(:button, name: "Save", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=upload-redirect"))
    end

    test "follows navigation returned by an upload progress callback with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/progress-redirect")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
      |> expect(Fluffy.Expect.page_to_have_url(Fluffy.TestServer.base_url() <> "/chamber?from=upload-progress"))
    end

    @tag driver: driver
    test "routes a managed upload through its owning nested LiveView with #{driver}", %{
      driver: driver
    } do
      child = by_css("#nested-child")

      driver
      |> start_test_session()
      |> visit("/live/nested")
      |> set_input_files(by_label(child, "Child attachment", exact: true), fixture_path())
      |> click(by_role(child, :button, name: "Upload child attachment", exact: true))
      |> expect(child |> by_text("Child uploaded: fluffy-upload.txt", exact: true) |> to_be_visible())
    end

    test "hands a managed upload form to HTTP after phx-trigger-action with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/trigger")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> click(by_role(:button, name: "Save", exact: true))
      |> expect("The guardian sleeps" |> by_text() |> to_be_visible())
    end

    test "submits the title captured when a managed upload starts with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/disable-title-on-progress")
      |> fill(by_label("Title"), "Ada")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> click(by_role(:button, name: "Save", exact: true))
      |> expect("Saved title: Ada" |> by_text() |> to_be_visible())
    end

    test "auto uploads one local file before submit with #{driver}" do
      file = fixture_path()

      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/auto")
      |> set_input_files(by_label("Attachment"), file)
      |> expect("Validated: true" |> by_text() |> to_be_visible())
      |> expect("Progress: 100" |> by_text() |> to_be_visible())
      |> expect("Completed uploads: 1" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
      |> expect("Completed uploads: 1" |> by_text() |> to_be_visible())
    end

    test "auto uploads two selected files before submit with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/auto-multiple")
      |> set_input_files(by_label("Attachment"), [fixture_path(), second_fixture_path()])
      |> expect("Completed uploads: 2" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
      |> expect(
        "Consumed: fluffy-upload-second.txt / Fluffy's second chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
      |> expect("Completed uploads: 2" |> by_text() |> to_be_visible())
    end

    test "auto uploads files selected in separate changes with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/auto-multiple")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> expect("Completed uploads: 1" |> by_text() |> to_be_visible())
      |> set_input_files(by_label("Attachment"), second_fixture_path())
      |> expect("Completed uploads: 2" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
      |> expect(
        "Consumed: fluffy-upload-second.txt / Fluffy's second chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
    end

    test "uploads and consumes two selected files in order with #{driver}" do
      files = [fixture_path(), second_fixture_path()]

      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/multiple")
      |> set_input_files(by_label("Attachment"), files)
      |> expect("Validated: true" |> by_text() |> to_be_visible())
      |> expect("Pending uploads: 2" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Completed uploads: 2" |> by_text() |> to_be_visible())
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
      |> expect(
        "Consumed: fluffy-upload-second.txt / Fluffy's second chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
    end

    test "rejects too many selected files with #{driver}" do
      files = [fixture_path(), second_fixture_path()]

      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/multiple")
      |> set_input_files(by_label("Attachment"), files ++ [fixture_path()])
      |> expect("Upload errors: 1" |> by_text() |> to_be_visible())
      |> expect("Completed uploads: 0" |> by_text() |> to_be_visible())
    end

    test "accumulates files selected in separate changes with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/multiple")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> expect("Pending uploads: 1" |> by_text() |> to_be_visible())
      |> set_input_files(by_label("Attachment"), second_fixture_path())
      |> expect("Pending uploads: 2" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Completed uploads: 2" |> by_text() |> to_be_visible())
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
      |> expect(
        "Consumed: fluffy-upload-second.txt / Fluffy's second chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
    end

    test "selection change can remove its upload form with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/remove-on-validate")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> expect("#upload-form" |> by_css() |> to_have_count(0))
      |> expect("Validated: true" |> by_text() |> to_be_visible())
      |> expect("Completed uploads: 0" |> by_text() |> to_be_visible())
    end

    test "rejects one invalid-extension file with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), invalid_fixture_path())
      |> expect("Upload errors: 1" |> by_text() |> to_be_visible())
      |> expect("Completed uploads: 0" |> by_text() |> to_be_visible())
    end

    test "valid selection replaces rejected selection with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), invalid_fixture_path())
      |> expect("Upload errors: 1" |> by_text() |> to_be_visible())
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> expect("Upload errors: 0" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Completed uploads: 1" |> by_text() |> to_be_visible())
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
    end

    test "rejects one oversized file with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/oversized")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> expect("Upload errors: 1" |> by_text() |> to_be_visible())
      |> expect("Completed uploads: 0" |> by_text() |> to_be_visible())
    end

    test "rejects each oversized file in a multi-entry selection with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/multiple-oversized")
      |> set_input_files(by_label("Attachment"), [fixture_path(), second_fixture_path()])
      |> expect("Upload errors: 2" |> by_text() |> to_be_visible())
      |> expect("Completed uploads: 0" |> by_text() |> to_be_visible())
    end

    test "uploads the valid entry after cancelling an invalid sibling with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/multiple")
      |> set_input_files(by_label("Attachment"), [fixture_path(), invalid_fixture_path()])
      |> expect("Upload errors: 1" |> by_text() |> to_be_visible())
      |> expect("Pending uploads: 2" |> by_text() |> to_be_visible())
      |> click(:button |> by_role(name: "Cancel upload", exact: true) |> nth(1))
      |> expect("Pending uploads: 1" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Completed uploads: 1" |> by_text() |> to_be_visible())
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
    end

    test "leaves a mixed selection pending when submitted before its invalid entry is cancelled with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/multiple")
      |> set_input_files(by_label("Attachment"), [fixture_path(), invalid_fixture_path()])
      |> expect("Upload errors: 1" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Pending uploads: 2" |> by_text() |> to_be_visible())
      |> expect("Completed uploads: 0" |> by_text() |> to_be_visible())
    end

    test "cancels one selected upload before submit with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> expect("Pending uploads: 1" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Cancel upload", exact: true))
      |> expect("Pending uploads: 0" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Submitted without input: true" |> by_text() |> to_be_visible())
      |> expect("Completed uploads: 0" |> by_text() |> to_be_visible())
    end

    test "clearing the file input does not cancel its pending LiveView entry with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> expect("Pending uploads: 1" |> by_text() |> to_be_visible())
      |> set_input_files(by_label("Attachment"), [])
      |> expect("Pending uploads: 1" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Completed uploads: 1" |> by_text() |> to_be_visible())
      |> expect(
        "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
    end

    test "cancels one of two selected uploads without discarding the other with #{driver}" do
      unquote(driver)
      |> start_test_session()
      |> visit("/live/scrolls/multiple")
      |> set_input_files(by_label("Attachment"), [fixture_path(), second_fixture_path()])
      |> expect("Pending uploads: 2" |> by_text() |> to_be_visible())
      |> click(:button |> by_role(name: "Cancel upload", exact: true) |> nth(0))
      |> expect("Pending uploads: 1" |> by_text() |> to_be_visible())
      |> click(by_role(:button, name: "Save"))
      |> expect("Completed uploads: 1" |> by_text() |> to_be_visible())
      |> expect(
        "Consumed: fluffy-upload-second.txt / Fluffy's second chamber secret, sealed for upload."
        |> by_text()
        |> to_be_visible()
      )
      |> expect("Consumed: fluffy-upload.txt" |> by_text() |> to_be_visible() |> not_())
    end

    for mode <- [:remove, :replace] do
      @tag driver: driver
      test "does not upload a stale selected file after its input is #{mode} with #{driver}" do
        file = fixture_path()

        unquote(driver)
        |> start_test_session()
        |> visit("/live/scrolls/#{unquote(mode)}")
        |> set_input_files(by_label("Attachment"), file)
        |> click(by_role(:button, name: input_mutation_label(unquote(mode))))
        |> click(by_role(:button, name: "Save"))
        |> expect("Submitted without input: true" |> by_text() |> to_be_visible())
        |> expect("Completed uploads: 0" |> by_text() |> to_be_visible())
      end
    end
  end

  test "releases the Live upload client when selection change removes its form" do
    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/scrolls/remove-on-validate")
      |> set_input_files(by_label("Attachment"), fixture_path())

    assert upload_clients(session) == []
    assert UploadState.empty?(Session.page_state(session).live_uploads)
  end

  test "releases the rejected Live upload client before replacing its selection" do
    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), invalid_fixture_path())

    [rejected_client] = upload_clients(session)

    session = set_input_files(session, by_label("Attachment"), fixture_path())

    assert [replacement_client] = upload_clients(session)
    refute replacement_client == rejected_client
    refute Process.alive?(rejected_client)
  end

  test "releases a managed upload client after a successful Phoenix submit" do
    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), fixture_path())

    [upload_client] = upload_clients(session)
    assert Process.alive?(upload_client)

    session
    |> click(by_role(:button, name: "Save"))
    |> expect(
      "Consumed: fluffy-upload.txt / Fluffy's first chamber secret, sealed for upload."
      |> by_text()
      |> to_be_visible()
    )

    assert upload_clients(session) == []
    refute Process.alive?(upload_client)
  end

  test "releases a managed upload client before following a Phoenix redirect" do
    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/scrolls/redirect")
      |> set_input_files(by_label("Attachment"), fixture_path())

    [upload_client] = upload_clients(session)

    session
    |> click(by_role(:button, name: "Save", exact: true))
    |> expect("The guardian sleeps" |> by_text() |> to_be_visible())

    refute Process.alive?(upload_client)
  end

  test "releases a managed upload client after Phoenix cancels its entry" do
    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), fixture_path())

    [upload_client] = upload_clients(session)

    session =
      session
      |> click(by_role(:button, name: "Cancel upload", exact: true))
      |> expect("Pending uploads: 0" |> by_text() |> to_be_visible())

    assert upload_clients(session) == []
    refute Process.alive?(upload_client)
    assert UploadState.empty?(Session.page_state(session).live_uploads)
  end

  test "keeps the managed upload client for an uncancelled Phoenix entry" do
    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/scrolls/multiple")
      |> set_input_files(by_label("Attachment"), [fixture_path(), second_fixture_path()])

    [upload_client] = upload_clients(session)

    session =
      session
      |> click(:button |> by_role(name: "Cancel upload", exact: true) |> nth(0))
      |> expect("Pending uploads: 1" |> by_text() |> to_be_visible())

    assert upload_clients(session) == [upload_client]
    assert Process.alive?(upload_client)

    session
    |> click(by_role(:button, name: "Save"))
    |> expect("Completed uploads: 1" |> by_text() |> to_be_visible())

    assert upload_clients(session) == []
    refute Process.alive?(upload_client)
  end

  test "releases every Phoenix upload client accumulated through separate selections" do
    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/scrolls/multiple")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> set_input_files(by_label("Attachment"), second_fixture_path())

    [first_client, second_client] = upload_clients(session)
    assert Process.alive?(first_client)
    assert Process.alive?(second_client)

    session
    |> click(by_role(:button, name: "Save"))
    |> expect("Completed uploads: 2" |> by_text() |> to_be_visible())

    assert upload_clients(session) == []
    refute Process.alive?(first_client)
    refute Process.alive?(second_client)
  end

  test "releases a managed upload client when Phoenix navigation replaces the document" do
    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), fixture_path())

    [upload_client] = upload_clients(session)

    session = visit(session, "/live/three-heads")

    assert upload_clients(session) == []
    refute Process.alive?(upload_client)
  end

  test "scope teardown releases a managed upload client after an assertion failure" do
    session =
      :phoenix
      |> start_test_session()
      |> visit("/live/scrolls")
      |> set_input_files(by_label("Attachment"), fixture_path())

    [upload_client] = upload_clients(session)
    scope = TestScope.current()

    assert_raise ExUnit.AssertionError, fn ->
      expect(session, "not rendered" |> by_text() |> to_be_visible(), timeout: 0)
    end

    trap_exits? = Process.flag(:trap_exit, true)

    try do
      :ok = GenServer.stop(scope)
      refute Process.alive?(upload_client)
    after
      Process.flag(:trap_exit, trap_exits?)
    end
  end

  defp start_test_session(driver) do
    start_session(driver,
      base_url: Fluffy.TestServer.base_url(),
      endpoint: Fluffy.TestWeb.Endpoint
    )
  end

  defp fixture_path do
    Path.expand("../support/fixtures/fluffy-upload.txt", __DIR__)
  end

  defp invalid_fixture_path do
    Path.expand("../support/fixtures/fluffy-upload.invalid", __DIR__)
  end

  defp second_fixture_path do
    Path.expand("../support/fixtures/fluffy-upload-second.txt", __DIR__)
  end

  defp input_mutation_label(:remove), do: "Remove attachment"
  defp input_mutation_label(:replace), do: "Replace attachment"

  defp upload_clients(session) do
    TestScope.current()
    |> TestScope.status()
    |> get_in([:sessions, session.context.resource_id])
    |> Enum.flat_map(fn
      {:upload_client, pid} -> [pid]
      _resource -> []
    end)
  end
end
