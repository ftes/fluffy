defmodule Fluffy.StepTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Playwright
  alias Fluffy.TestScope

  for backend <- [:phoenix, :playwright] do
    @tag backend: backend
    test "returns the callback's updated session with #{backend}", %{backend: backend} do
      session =
        backend
        |> start_session(
          endpoint: Fluffy.TestWeb.Endpoint,
          base_url: Fluffy.TestServer.base_url()
        )
        |> visit("/live/three-heads")
        |> step("Lull one of Fluffy's heads", fn session ->
          click(session, by_role(:button, name: "Play the flute"))
        end)

      expect(session, "Sleeping heads: 1" |> by_text() |> to_be_visible())
    end
  end

  test "records nested Playwright groups with source locations", context do
    directory = trace_directory(context)

    :playwright
    |> start_session(base_url: Fluffy.TestServer.base_url())
    |> Playwright.trace(directory: directory, name: "nested steps", open: false)
    |> visit("/stage")
    |> step("Outer workflow", fn session ->
      step(session, "Inner operation", fn session ->
        Playwright.evaluate(session, "document.body.dataset.stepped = 'yes'")
        session
      end)
    end)

    :ok = GenServer.stop(TestScope.current())

    assert [path] = Path.wildcard(Path.join(directory, "nested-steps-*.zip"))
    trace = trace_contents(path)
    assert trace =~ "Outer workflow"
    assert trace =~ "Inner operation"
    assert trace =~ Path.absname(__ENV__.file)
  end

  test "runs directly when a Playwright trace was not enabled" do
    session = start_session(:playwright, base_url: Fluffy.TestServer.base_url())

    assert ^session = step(session, "No trace", & &1)
  end

  defp trace_contents(path) do
    {:ok, handle} = :zip.zip_open(String.to_charlist(path), [:memory])
    {:ok, {_, contents}} = :zip.zip_get(~c"trace.trace", handle)
    :ok = :zip.zip_close(handle)
    contents
  end

  defp trace_directory(context) do
    path =
      Path.join(
        System.tmp_dir!(),
        "fluffy-step-test-#{context.test}-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
