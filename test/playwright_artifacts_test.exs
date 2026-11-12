defmodule Fluffy.PlaywrightArtifactsTest do
  # Fluffy's side of PlaywrightEx.Test's recording: contexts that sessions create in their
  # runtime processes are the test's, and steps are its test steps. PlaywrightEx.Test merges
  # `trace.zip` in its own `on_exit`, so the assertions run in one registered before it.
  use ExUnit.Case, async: true
  use Fluffy.Test, sandbox: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright

  alias Fluffy.Event
  alias Fluffy.FilePayload
  alias Fluffy.Playwright
  alias Fluffy.Support.HTTPFixtures
  alias Fluffy.Support.Server

  # Derived, so the trace's copy of this source file does not contain it.
  @secret "FLUFFY-" <> Base.encode16("upload secret of gringotts")

  setup context do
    path = PlaywrightEx.Test.output_path(context, "trace.zip")

    on_exit(fn ->
      trace = read_trace(path)
      File.rm_rf!(Path.dirname(path))
      for expected <- context[:trace_has] || [], do: assert(trace =~ expected)
      for unexpected <- context[:trace_lacks] || [], do: refute(trace =~ unexpected)
    end)

    PlaywrightEx.Test.record_artifacts(context, trace: :on)
  end

  @tag trace_has: [
         ~s("method":"goto"),
         ~s(internal:role=button[name=\\"Open popup\\"i]),
         ~s(Traced popup),
         ~s("url":"/stage")
       ]
  test "records every page of every session into the test's trace" do
    fixture =
      HTTPFixtures.register(fn request ->
        case request.path do
          "/start" -> %{body: html(~s|<button onclick="window.open('popup')">Open popup</button>|)}
          "/popup" -> %{body: html("<h1>Traced popup</h1>")}
        end
      end)

    :playwright
    |> start_session(base_url: Server.base_url())
    |> visit(HTTPFixtures.path(fixture, "/start"))
    |> then(fn session ->
      pending = wait_for(session, Event.popup())
      click(session, by_role(:button, name: "Open popup"))
      switch_page(session, await(pending))
    end)
    |> expect("Traced popup" |> by_text() |> to_be_visible())

    :playwright |> start_session(base_url: Server.base_url()) |> visit("/stage")
  end

  @tag trace_has: ["Outer workflow", "Inner operation", Path.absname(__ENV__.file)]
  test "records steps as nested test steps with source locations" do
    :playwright
    |> start_session(base_url: Server.base_url())
    |> visit("/stage")
    |> step("Outer workflow", fn session ->
      step(session, "Inner operation", fn session ->
        Playwright.evaluate(session, "document.body.dataset.stepped = 'yes'")
        session
      end)
    end)
  end

  @tag trace_has: ["set_input_files", "setInputFiles"], trace_lacks: [@secret]
  test "does not copy in-memory upload contents into the trace" do
    :playwright
    |> session_for_html(~s(<label>Attachment <input type="file"></label>), base_url: Server.base_url())
    |> set_input_files(by_label("Attachment"), %FilePayload{
      name: "private.txt",
      bytes: @secret,
      content_type: "text/plain"
    })
  end

  # Every entry, as the archive of several contexts prefixes each one's `trace.trace`.
  defp read_trace(path) do
    {:ok, entries} = :zip.extract(String.to_charlist(path), [:memory])
    Enum.map_join(entries, "\n", fn {_name, contents} -> contents end)
  end

  defp html(body), do: "<!doctype html><html><body>#{body}</body></html>"
end
