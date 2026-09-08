defmodule Fluffy.Conformance.FileInputActionTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.FilePayload
  alias Fluffy.Playwright
  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "selects one local file and submits its multipart part with #{driver}" do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit" enctype="multipart/form-data">
                <label>Title <input name="title" value="Initial"></label>
                <label>Attachment <input type="file" name="attachment"></label>
                <button name="commit" value="Save">Save</button>
              </form>
              """)
          },
          %{body: html("<h1>Uploaded</h1>")}
        ])

      file = fixture_path()
      bytes = File.read!(file)

      session = start_test_session(unquote(driver))

      session
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> fill(by_label("Title"), "Release notes")
      |> set_input_files(by_label("Attachment"), file)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)

      assert {"content-type", "multipart/form-data; boundary=" <> boundary} =
               List.keyfind(submission.headers, "content-type", 0)

      assert submission.body ==
               "--#{boundary}\r\n" <>
                 "Content-Disposition: form-data; name=\"title\"\r\n\r\n" <>
                 "Release notes\r\n" <>
                 "--#{boundary}\r\n" <>
                 ~s(Content-Disposition: form-data; name="attachment"; filename="fluffy-upload.txt"\r\n) <>
                 "Content-Type: text/plain\r\n\r\n" <>
                 bytes <>
                 "\r\n" <>
                 "--#{boundary}\r\n" <>
                 "Content-Disposition: form-data; name=\"commit\"\r\n\r\n" <>
                 "Save\r\n" <>
                 "--#{boundary}--\r\n"

      refute submission.body =~ file
    end

    test "selects one in-memory payload and submits its exact bytes with #{driver}" do
      fixture = upload_fixture()

      payload = %FilePayload{
        name: "generated.csv",
        bytes: <<0, 1, 2, "name,total\nAda,42\n">>,
        content_type: "text/csv"
      }

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), payload)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)

      assert submission.body =~
               ~s(Content-Disposition: form-data; name="attachment"; filename="generated.csv"\r\n) <>
                 "Content-Type: text/csv\r\n\r\n" <>
                 payload.bytes <>
                 "\r\n"
    end

    test "infers an in-memory payload content type from its filename with #{driver}" do
      fixture = upload_fixture()
      payload = %FilePayload{name: "generated.csv", bytes: "id\n42\n"}

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), payload)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body =~ "Content-Type: text/csv\r\n"
    end

    test "normalizes an in-memory payload MIME type like a browser File with #{driver}" do
      fixture = upload_fixture()

      payload = %FilePayload{
        name: "generated.data",
        bytes: "generated",
        content_type: "TEXT/PLAIN"
      }

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), payload)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body =~ "Content-Type: text/plain\r\n"
      refute submission.body =~ "Content-Type: TEXT/PLAIN\r\n"
    end

    test "falls back safely for an invalid browser File MIME type with #{driver}" do
      fixture = upload_fixture()

      payload = %FilePayload{
        name: "generated.data",
        bytes: "generated",
        content_type: "text/plain\r\nX-Injected: true"
      }

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), payload)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body =~ "Content-Type: application/octet-stream\r\n"
      refute submission.body =~ "X-Injected"
    end

    test "escapes browser multipart filename parameters with #{driver}" do
      fixture = upload_fixture()

      payload = %FilePayload{
        name: "report\"\r\nnext.txt",
        bytes: "generated",
        content_type: "text/plain"
      }

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), payload)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body =~ ~s(filename="report%22%0D%0Anext.txt")
      refute submission.body =~ "\r\nnext.txt"
    end

    test "selects multiple local files in order and submits repeated multipart parts with #{driver}" do
      fixture = multiple_upload_fixture()
      files = [fixture_path(), invalid_fixture_path()]

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachments"), files)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)

      assert_file_parts_in_order(submission.body, files)
    end

    test "selects multiple in-memory payloads in order with #{driver}" do
      fixture = multiple_upload_fixture()

      payloads = [
        %FilePayload{name: "first.txt", bytes: "first", content_type: "text/plain"},
        %FilePayload{name: "second.bin", bytes: <<0, 255>>, content_type: "application/x-test"}
      ]

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachments"), payloads)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      first = :binary.match(submission.body, ~s(filename="first.txt"))
      second = :binary.match(submission.body, ~s(filename="second.bin"))
      assert elem(first, 0) < elem(second, 0)
      assert submission.body =~ "first"
      assert submission.body =~ <<0, 255>>
    end

    test "clears a selected FileList before multipart submission with #{driver}" do
      fixture = multiple_upload_fixture()
      files = [fixture_path(), invalid_fixture_path()]

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachments"), files)
      |> set_input_files(by_label("Attachments"), [])
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)

      assert String.contains?(submission.body, ~s(name="attachment"; filename=""))
      assert occurrence_count(submission.body, ~s(name="attachment")) == 1
      refute submission.body =~ File.read!(fixture_path())
      refute submission.body =~ File.read!(invalid_fixture_path())
    end

    test "a form reset discards its selected FileList with #{driver}" do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit" enctype="multipart/form-data">
                <label>Attachment <input type="file" name="attachment"></label>
                <button type="reset">Reset</button>
                <button name="commit" value="Save">Save</button>
              </form>
              """)
          },
          %{body: html("<h1>Uploaded</h1>")}
        ])

      file = fixture_path()

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), file)
      |> click(by_role(:button, name: "Reset"))
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body =~ ~s(name="attachment"; filename="")
      refute submission.body =~ "fluffy-upload.txt"
      refute submission.body =~ File.read!(file)
    end

    test "rejects multiple selection on a single-file input without replacing its selection with #{driver}" do
      fixture = upload_fixture()
      file = fixture_path()

      session =
        unquote(driver)
        |> start_test_session()
        |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
        |> set_input_files(by_label("Attachment"), file)

      error =
        assert_raise Fluffy.ActionabilityError, fn ->
          set_input_files(session, by_label("Attachment"), [file, invalid_fixture_path()])
        end

      assert error.action == :set_input_files
      assert error.reason == :multiple_files_not_allowed

      session
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)
      assert_file_parts_in_order(submission.body, [file])
    end

    @tag driver: driver
    test "does not submit a selected file after its control is disabled with #{driver}" do
      fixture = upload_fixture()
      file = fixture_path()

      session = start_test_session(unquote(driver))

      session
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), file)
      |> mutate_file_control(unquote(driver), :disable)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      assert_file_omitted(TestHTTPFixtures.requests(fixture), file)
    end

    @tag driver: driver
    test "can select a disabled file input but omits it from submission with #{driver}" do
      fixture =
        TestHTTPFixtures.register_sequence([
          %{
            body:
              html("""
              <form method="post" action="submit" enctype="multipart/form-data">
                <label>Attachment <input type="file" name="attachment" disabled></label>
                <button name="commit" value="Save">Save</button>
              </form>
              """)
          },
          %{body: html("<h1>Uploaded</h1>")}
        ])

      file = fixture_path()

      unquote(driver)
      |> start_test_session()
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), file)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      assert_file_omitted(TestHTTPFixtures.requests(fixture), file)
    end

    @tag driver: driver
    test "does not submit a selected file after its control is removed with #{driver}" do
      fixture = upload_fixture()
      file = fixture_path()

      session = start_test_session(unquote(driver))

      session
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), file)
      |> mutate_file_control(unquote(driver), :remove)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      assert_file_omitted(TestHTTPFixtures.requests(fixture), file)
    end

    @tag driver: driver
    test "submits an empty file part after its selected control is replaced with #{driver}" do
      fixture = upload_fixture()
      file = fixture_path()

      session = start_test_session(unquote(driver))

      session
      |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
      |> set_input_files(by_label("Attachment"), file)
      |> mutate_file_control(unquote(driver), :replace)
      |> click(by_role(:button, name: "Save"))
      |> expect(visible(by_text("Uploaded")))

      [_source, submission] = TestHTTPFixtures.requests(fixture)

      assert submission.body =~
               ~s(Content-Disposition: form-data; name="attachment"; filename=""\r\n) <>
                 "Content-Type: application/octet-stream\r\n\r\n\r\n"

      refute submission.body =~ "fluffy-upload.txt"
      refute submission.body =~ File.read!(file)
    end

    for {status, redirected_method} <- [
          {301, "GET"},
          {302, "GET"},
          {303, "GET"},
          {307, "POST"},
          {308, "POST"}
        ] do
      @tag driver: driver
      test "follows HTTP #{status} after selected multipart submission with #{driver}" do
        fixture = redirect_upload_fixture(unquote(status))
        file = fixture_path()

        session = start_test_session(unquote(driver))

        session
        |> visit(TestHTTPFixtures.path(fixture, "/upload/start"))
        |> set_input_files(by_label("Attachment"), file)
        |> click(by_role(:button, name: "Save"))
        |> expect(visible(by_text("Redirected upload")))

        [_source, submission, redirected] = TestHTTPFixtures.requests(fixture)
        assert submission.method == "POST"
        assert submission.body =~ "filename=\"fluffy-upload.txt\""
        assert submission.body =~ File.read!(file)
        assert redirected.method == unquote(redirected_method)

        if redirected.method == "POST" do
          assert redirected.body == submission.body

          assert List.keyfind(redirected.headers, "content-type", 0) ==
                   List.keyfind(submission.headers, "content-type", 0)
        else
          assert redirected.body == ""
          refute List.keymember?(redirected.headers, "content-type", 0)
        end
      end
    end
  end

  test "preflights the complete argument before changing the page" do
    session =
      session_for_html(
        :static,
        ~s(<label>Attachments <input type="file" name="attachment" multiple></label>)
      )

    payload = %FilePayload{name: "secret.txt", bytes: "DO NOT LEAK THIS CONTENT"}

    error =
      assert_raise ArgumentError, fn ->
        set_input_files(session, by_label("Attachments"), [payload, fixture_path()])
      end

    assert error.message =~ "homogeneous"
    refute error.message =~ payload.bytes

    session
    |> set_input_files(by_label("Attachments"), payload)
    |> set_input_files(by_label("Attachments"), [])
  end

  test "rejects selections above the configured byte bound without exposing contents" do
    session =
      session_for_html(
        :static,
        ~s(<label>Attachment <input type="file" name="attachment"></label>)
      )

    payload = %FilePayload{name: "secret.txt", bytes: "sensitive"}

    error =
      assert_raise ArgumentError, fn ->
        set_input_files(session, by_label("Attachment"), payload, max_bytes: 4)
      end

    assert error.message =~ "9 bytes"
    assert error.message =~ ":max_bytes limit of 4"
    refute error.message =~ payload.bytes
  end

  test "preflights every local path and its aggregate byte bound" do
    session =
      session_for_html(
        :static,
        ~s(<label>Attachments <input type="file" name="attachment" multiple></label>)
      )

    missing = Path.join(System.tmp_dir!(), "fluffy-missing-#{System.unique_integer()}")

    assert_raise ArgumentError, ~r/could not stat/, fn ->
      set_input_files(session, by_label("Attachments"), [fixture_path(), missing])
    end

    assert_raise ArgumentError, ~r/readable regular file/, fn ->
      set_input_files(session, by_label("Attachments"), System.tmp_dir!())
    end

    size = File.stat!(fixture_path()).size

    assert_raise ArgumentError, ~r/exceeding :max_bytes limit/, fn ->
      set_input_files(session, by_label("Attachments"), fixture_path(), max_bytes: size - 1)
    end
  end

  test "rejects malformed payloads and map aliases" do
    session =
      session_for_html(
        :static,
        ~s(<label>Attachment <input type="file" name="attachment"></label>)
      )

    assert_raise ArgumentError, ~r/Fluffy.FilePayload/, fn ->
      set_input_files(session, by_label("Attachment"), %{name: "old-shape.txt", bytes: "x"})
    end

    assert_raise ArgumentError, ~r/binary :name and :bytes/, fn ->
      set_input_files(
        session,
        by_label("Attachment"),
        struct(FilePayload, name: :invalid, bytes: "x")
      )
    end
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "set_input_files rejects a non-file target with #{driver}" do
      session =
        session_for_html(
          unquote(driver),
          ~s(<label>Attachment <input name="attachment" type="text"></label>),
          base_url: Fluffy.TestServer.base_url()
        )

      error =
        assert_raise Fluffy.ActionabilityError, fn ->
          set_input_files(session, by_label("Attachment"), fixture_path())
        end

      assert error.action == :set_input_files
      assert error.reason == :not_file_input
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

  defp upload_fixture do
    TestHTTPFixtures.register_sequence([
      %{
        body:
          html("""
          <form method="post" action="submit" enctype="multipart/form-data">
            <label>Attachment <input id="attachment" type="file" name="attachment"></label>
            <button name="commit" value="Save">Save</button>
          </form>
          """)
      },
      %{body: html("<h1>Uploaded</h1>")}
    ])
  end

  defp multiple_upload_fixture do
    TestHTTPFixtures.register_sequence([
      %{
        body:
          html("""
          <form method="post" action="submit" enctype="multipart/form-data">
            <label>Attachments <input id="attachment" type="file" name="attachment" multiple></label>
            <button name="commit" value="Save">Save</button>
          </form>
          """)
      },
      %{body: html("<h1>Uploaded</h1>")}
    ])
  end

  defp redirect_upload_fixture(status) do
    TestHTTPFixtures.register_sequence([
      %{
        body:
          html("""
          <form method="post" action="submit" enctype="multipart/form-data">
            <label>Attachment <input id="attachment" type="file" name="attachment"></label>
            <button name="commit" value="Save">Save</button>
          </form>
          """)
      },
      %{status: status, headers: [{"location", "receipt"}]},
      %{body: html("<h1>Redirected upload</h1>")}
    ])
  end

  defp mutate_file_control(session, :phoenix, operation) do
    set_html(session, upload_markup(operation))
  end

  defp mutate_file_control(session, :playwright, :disable) do
    Playwright.evaluate(
      session,
      "document.querySelector('#attachment').disabled = true"
    )

    session
  end

  defp mutate_file_control(session, :playwright, :remove) do
    Playwright.evaluate(session, "document.querySelector('#attachment').remove()")
    session
  end

  defp mutate_file_control(session, :playwright, :replace) do
    Playwright.evaluate(
      session,
      """
      const old = document.querySelector('#attachment');
      const input = document.createElement('input');
      input.id = old.id;
      input.type = old.type;
      input.name = old.name;
      old.replaceWith(input)
      """
    )

    session
  end

  defp upload_markup(:disable) do
    html("""
    <form method="post" action="submit" enctype="multipart/form-data">
      <label>Attachment <input id="attachment" type="file" name="attachment" disabled></label>
      <button name="commit" value="Save">Save</button>
    </form>
    """)
  end

  defp upload_markup(:remove) do
    html("""
    <form method="post" action="submit" enctype="multipart/form-data">
      <label>Attachment</label>
      <button name="commit" value="Save">Save</button>
    </form>
    """)
  end

  defp upload_markup(:replace) do
    html("""
    <form method="post" action="submit" enctype="multipart/form-data">
      <label>Attachment <input id="attachment" type="file" name="attachment"></label>
      <button name="commit" value="Save">Save</button>
    </form>
    """)
  end

  defp assert_file_omitted([_source, submission], file) do
    refute submission.body =~ "name=\"attachment\""
    refute submission.body =~ "fluffy-upload.txt"
    refute submission.body =~ File.read!(file)
  end

  defp assert_file_parts_in_order(body, paths) do
    {positions, _offset} =
      Enum.map_reduce(paths, 0, fn path, offset ->
        filename = Path.basename(path)
        bytes = File.read!(path)
        part = ~s(name="attachment"; filename="#{filename}")

        position = :binary.match(body, part, scope: {offset, byte_size(body) - offset})
        assert {index, _length} = position
        assert body =~ bytes
        {index, index + 1}
      end)

    assert positions == Enum.sort(positions)
    assert occurrence_count(body, ~s(name="attachment")) == length(paths)
  end

  defp occurrence_count(body, part), do: body |> String.split(part) |> length() |> Kernel.-(1)

  defp html(body), do: "<!doctype html><html><body><main>#{body}</main></body></html>"
end
