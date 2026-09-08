defmodule Fluffy.Conformance.CSSLocatorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "re-resolves a CSS locator against the current document with #{driver}", %{
      driver: driver
    } do
      item = by_css(".item")

      session =
        session_for_html(driver, ~s(<div class="item">First</div>), base_url: Fluffy.TestServer.base_url())

      session
      |> expect(to_have_count(item, 1))
      |> set_html(~s(<div class="item">First</div><div class="item">Second</div>))
      |> expect(to_have_count(item, 2))
    end
  end
end
