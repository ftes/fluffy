defmodule Fluffy.PlaywrightScreenshotTest do
  use Fluffy.Support.Case, async: true

  import Fluffy

  alias Fluffy.Playwright

  @tag :tmp_dir
  test "returns the screenshot and writes it to path:", %{tmp_dir: tmp_dir} do
    path = Path.join(tmp_dir, "screenshots/page.png")

    session =
      :playwright
      |> start_session(base_url: Fluffy.Support.Server.base_url())
      |> visit("/chamber")

    assert <<137, 80, 78, 71, _rest::binary>> = png = Playwright.screenshot(session, path: path, full_page: true)
    assert File.read!(path) == png
    assert <<137, 80, 78, 71, _rest::binary>> = Playwright.screenshot(session)
  end

  test "rejects screenshots for Phoenix sessions" do
    session =
      :phoenix
      |> start_session(endpoint: Fluffy.Support.Web.Endpoint)
      |> visit("/chamber")

    assert_raise Fluffy.CapabilityError, ~r/:static does not support :screenshot/, fn ->
      Playwright.screenshot(session)
    end
  end
end
