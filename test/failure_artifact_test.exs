defmodule Fluffy.FailureArtifactTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Backend.Playwright.Bounded
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

  # A linked call would kill the caller, skipping capture's own error handling.
  @tag :capture_log
  test "a crash in a bounded Playwright call raises in the caller instead of killing it" do
    assert_raise RuntimeError, "boom", fn -> Bounded.within(1_000, fn -> raise "boom" end) end
    assert catch_exit(Bounded.within(1_000, fn -> exit(:boom) end)) == :boom
  end

  test "a bounded Playwright call past its timeout is killed, or left to finish" do
    owner = self()
    slow = fn -> fn -> send(owner, {:finished, Process.sleep(200)}) end end

    assert Bounded.within(10, slow.()) == :timeout
    refute_receive {:finished, :ok}, 400
    assert Bounded.within(10, slow.(), on_timeout: :leave) == :timeout
    assert_receive {:finished, :ok}, 400
  end

  @tag :capture_log
  test "a bounded Playwright call ends at a message, its result, a crash or its timeout" do
    owner = self()
    ref = make_ref()
    slow = fn -> send(owner, {:finished, Process.sleep(200)}) end

    send(owner, {ref, :stop, :value})
    assert Bounded.within_unless(1_000, slow, {ref, :stop}) == {:message, :value}
    refute_receive {:finished, :ok}, 400

    assert Bounded.within_unless(1_000, fn -> :done end, {ref, :stop}) == {:ok, :done}
    assert_raise RuntimeError, "boom", fn -> Bounded.within_unless(1_000, fn -> raise "boom" end, {ref, :stop}) end
    assert Bounded.within_unless(10, slow, {ref, :stop}) == :timeout
    refute_receive {:finished, :ok}, 400
  end
end
