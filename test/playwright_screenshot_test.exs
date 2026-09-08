defmodule Fluffy.PlaywrightScreenshotTest do
  use Fluffy.TestCase, async: true

  import Fluffy

  alias Fluffy.Playwright

  @tag :tmp_dir
  test "saves an explicit screenshot and remains pipeable", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "screenshots/page.png")

    session =
      :playwright
      |> start_session(base_url: Fluffy.TestServer.base_url())
      |> visit("/chamber")

    assert ^session = Playwright.screenshot(session, path, full_page: true)
    assert <<137, 80, 78, 71, _rest::binary>> = File.read!(path)
  end

  test "rejects screenshots for Phoenix sessions" do
    session =
      :phoenix
      |> start_session(endpoint: Fluffy.TestWeb.Endpoint)
      |> visit("/chamber")

    assert_raise Fluffy.CapabilityError, ~r/:static does not support :screenshot/, fn ->
      Playwright.screenshot(session, "unused.png")
    end
  end
end
