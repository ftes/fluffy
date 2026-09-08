defmodule Fluffy.Conformance.LiveFileInputTest do
  use Fluffy.TestCase, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestHTTPFixtures

  for driver <- [:phoenix, :playwright] do
    @tag driver: driver
    test "submits one selected file through an ordinary Live form navigation with #{driver}" do
      fixture = TestHTTPFixtures.register(%{body: html("<h1>Uploaded from Live</h1>")})
      file = fixture_path()
      action = TestHTTPFixtures.path(fixture, "/submit")

      session = start_test_session(unquote(driver))

      session
      |> visit("/live/file-navigation?action=#{URI.encode_www_form(action)}")
      |> set_input_files(by_label("Attachment"), file)
      |> click(by_role(:button, name: "Save"))
      |> expect("Uploaded from Live" |> by_text() |> to_be_visible())

      [submission] = TestHTTPFixtures.requests(fixture)

      assert submission.method == "POST"
      assert submission.body =~ "filename=\"fluffy-upload.txt\""
      assert submission.body =~ File.read!(file)
      refute submission.body =~ file
    end

    test "submits multiple selected files through an ordinary Live form navigation with #{driver}" do
      fixture = TestHTTPFixtures.register(%{body: html("<h1>Uploaded from Live</h1>")})
      files = [fixture_path(), invalid_fixture_path()]
      action = TestHTTPFixtures.path(fixture, "/submit")

      unquote(driver)
      |> start_test_session()
      |> visit("/live/file-navigation?action=#{URI.encode_www_form(action)}&multiple=true")
      |> set_input_files(by_label("Attachment"), files)
      |> click(by_role(:button, name: "Save"))
      |> expect("Uploaded from Live" |> by_text() |> to_be_visible())

      [submission] = TestHTTPFixtures.requests(fixture)

      assert submission.body =~ ~s(name="attachment"; filename="fluffy-upload.txt")
      assert submission.body =~ ~s(name="attachment"; filename="fluffy-upload.invalid")

      assert {:ok, txt_position} = index_of(submission.body, "fluffy-upload.txt")
      assert {:ok, invalid_position} = index_of(submission.body, "fluffy-upload.invalid")
      assert txt_position < invalid_position
    end

    test "clears a selected file before ordinary Live form navigation with #{driver}" do
      fixture = TestHTTPFixtures.register(%{body: html("<h1>Uploaded from Live</h1>")})
      action = TestHTTPFixtures.path(fixture, "/submit")

      unquote(driver)
      |> start_test_session()
      |> visit("/live/file-navigation?action=#{URI.encode_www_form(action)}")
      |> set_input_files(by_label("Attachment"), fixture_path())
      |> set_input_files(by_label("Attachment"), [])
      |> click(by_role(:button, name: "Save"))
      |> expect("Uploaded from Live" |> by_text() |> to_be_visible())

      [submission] = TestHTTPFixtures.requests(fixture)
      assert submission.body =~ ~s(name="attachment"; filename="")
      refute submission.body =~ "fluffy-upload.txt"
    end
  end

  test "retains the explicit LiveView-managed upload boundary" do
    session = :phoenix |> start_test_session() |> visit("/live/file-navigation?live_managed=true")

    error =
      assert_raise Fluffy.CapabilityError, fn ->
        set_input_files(session, by_label("Attachment"), fixture_path())
      end

    assert error.capability == :file_uploads
    assert error.driver == :live
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

  defp index_of(body, value) do
    case :binary.match(body, value) do
      {index, _length} -> {:ok, index}
      :nomatch -> :error
    end
  end

  defp html(body), do: "<!doctype html><html><body><main>#{body}</main></body></html>"
end
