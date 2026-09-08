defmodule Fluffy.Conformance.FileInputBrowserContractTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Locator

  alias Fluffy.FilePayload
  alias Fluffy.Playwright

  @tag driver: :playwright
  test "records Playwright payload metadata and fake-path value" do
    payload = %FilePayload{
      name: "generated.csv",
      bytes: "name,total\nAda,42\n",
      content_type: "TEXT/CSV"
    }

    session =
      ~s(<label>Attachment <input id="attachment" type="file"></label>)
      |> playwright_session()
      |> set_input_files(by_label("Attachment"), payload)

    metadata =
      Playwright.evaluate(
        session,
        """
        () => {
          const input = document.querySelector('#attachment');
          const file = input.files[0];
          return {
            name: file.name,
            type: file.type,
            size: file.size,
            lastModified: file.lastModified,
            value: input.value
          };
        }
        """,
        is_function: true
      )

    assert metadata["name"] == payload.name
    assert metadata["type"] == "text/csv"
    assert metadata["size"] == byte_size(payload.bytes)
    assert metadata["lastModified"] > 0
    assert metadata["value"] == "C:\\fakepath\\generated.csv"
  end

  @tag driver: :playwright
  test "records input then change for each Playwright file selection" do
    session =
      ~s(<label>Attachment <input id="attachment" type="file"></label>)
      |> playwright_session()
      |> then(fn session ->
        Playwright.evaluate(session, """
        window.fileEvents = [];
        const input = document.querySelector('#attachment');
        input.addEventListener('input', () => fileEvents.push('input'));
        input.addEventListener('change', () => fileEvents.push('change'));
        """)

        session
      end)

    payload = %FilePayload{name: "same.txt", bytes: "same"}

    session
    |> set_input_files(by_label("Attachment"), payload)
    |> set_input_files(by_label("Attachment"), payload)
    |> then(fn session ->
      assert Playwright.evaluate(session, "window.fileEvents") == [
               "input",
               "change",
               "input",
               "change"
             ]
    end)
  end

  defp playwright_session(html) do
    session_for_html(:playwright, html, base_url: Fluffy.TestServer.base_url())
  end
end
