defmodule Fluffy.Conformance.OpenBrowserTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.TestWeb.Endpoint

  for backend <- [:phoenix, :playwright] do
    @tag backend: backend
    test "opens the current static page without changing the #{backend} session", %{backend: backend} do
      session = backend |> start_session() |> visit("/chamber")

      html = snapshot(session)
      assert html =~ "The guardian sleeps"
      refute html =~ "<script"
      expect(session, "The guardian sleeps" |> by_text() |> to_be_visible())
    end

    @tag backend: backend
    test "opens updated LiveView content with #{backend}", %{backend: backend} do
      session =
        backend
        |> start_session()
        |> visit("/live/three-heads")
        |> click(by_role(:button, name: "Play the flute"))
        |> expect("Sleeping heads: 1" |> by_text() |> to_be_visible())

      assert snapshot(session) =~ "Sleeping heads: 1"
      refute snapshot(session) =~ "<script"
    end
  end

  test "static assets resolve through the session endpoint while links and remote assets remain intact" do
    session =
      :phoenix
      |> start_session(endpoint: Endpoint)
      |> visit("/chamber")
      |> set_html("""
      <link rel="stylesheet" href="/assets/app.css">
      <img src="//example.org/image.png">
      <a href="/destination">Link<script>ignored()</script></a>
      """)

    html = snapshot(session)
    assert html =~ "file://#{Application.app_dir(:fluffy, "priv/static/assets/app.css")}"
    assert html =~ "//example.org/image.png"
    assert html =~ "href=\"/destination\""
    refute html =~ "<script"
  end

  test "browser snapshots resolve relative assets and use the active page" do
    session = :playwright |> start_session() |> visit("/chamber")
    session = session |> switch_page(new_page(session)) |> visit("/chamber")

    Fluffy.Playwright.evaluate(session, """
    document.body.innerHTML = '<img src="assets/image.png"><p>Second page</p>'
    """)

    html = snapshot(session)
    assert html =~ "Second page"
    assert html =~ Fluffy.TestServer.base_url() <> "/assets/image.png"
  end

  test "requires a visited Phoenix page" do
    session = start_session(:phoenix)

    assert_raise ArgumentError, ~r/visit a page/, fn ->
      open_browser(session, fn _path -> flunk("unexpected snapshot") end)
    end
  end

  defp snapshot(session) do
    ref = make_ref()

    assert open_browser(session, fn path -> send(self(), {ref, path}) end) == session
    assert_receive {^ref, path}
    on_exit(fn -> File.rm(path) end)
    File.read!(path)
  end
end
