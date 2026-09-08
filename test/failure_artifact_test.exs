defmodule Fluffy.FailureArtifactTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.FailureArtifact

  @tag :tmp_dir
  test "captures Playwright HTML, screenshot, and failure text without changing the error", %{
    tmp_dir: tmp_dir
  } do
    session =
      session_for_html(:playwright, "<main><h1>Artifact page</h1></main>", base_url: Fluffy.TestServer.base_url())

    error = RuntimeError.exception("original failure")
    assert :ok = FailureArtifact.capture(session, :expect, error, [], tmp_dir)

    assert [html] = Path.wildcard(Path.join(tmp_dir, "*-expect-*.html"))
    assert [png] = Path.wildcard(Path.join(tmp_dir, "*-expect-*.png"))
    assert [failure] = Path.wildcard(Path.join(tmp_dir, "*-expect-*.txt"))

    assert Path.basename(html) =~ "failure-artifact-test"

    assert File.read!(html) =~ "Artifact page"
    assert png |> File.read!() |> byte_size() > 0
    assert File.read!(failure) =~ "original failure"
  end
end
