defmodule Fluffy.Conformance.TestIdAttributeTest do
  # Playwright Test's `testIdAttribute`, `config :fluffy, test_id_attribute:` over PlaywrightEx's,
  # is global config.
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright, only: [unwrap_and_return: 3]

  alias Fluffy.Session
  alias Fluffy.Support.Server
  alias PlaywrightEx.Isomorphic.LocatorUtils

  @owlery ~s(<section id="owlery"><p data-owl="hedwig">Hedwig</p><p data-testid="errol">Errol</p></section>)

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "#{driver} matches the configured attribute", %{driver: driver} do
      put_fluffy_config(test_id_attribute: "data-owl")

      driver
      |> session_for_html(@owlery, base_url: Server.base_url())
      |> expect("hedwig" |> by_test_id() |> to_have_text("Hedwig"))
      |> expect("errol" |> by_test_id() |> to_have_count(0))
      |> expect("#owlery" |> by_css() |> by_test_id("hedwig") |> to_have_count(1))
    end

    # As upstream's test id engine, a comma-separated list matches any of its attributes.
    @tag driver: driver
    test "#{driver} matches any attribute of a comma-separated list", %{driver: driver} do
      put_fluffy_config(test_id_attribute: "data-owl,data-testid")

      driver
      |> session_for_html(@owlery, base_url: Server.base_url())
      |> expect("hedwig" |> by_test_id() |> to_have_text("Hedwig"))
      |> expect("errol" |> by_test_id() |> to_have_text("Errol"))
    end
  end

  # Fluffy's unset (the suite's config): PlaywrightEx's, on every driver.
  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "#{driver} falls back to PlaywrightEx's attribute", %{driver: driver} do
      put_playwright_ex_config(:test, test_id_attribute: "data-owl")

      driver
      |> session_for_html(@owlery, base_url: Server.base_url())
      |> expect("hedwig" |> by_test_id() |> to_have_text("Hedwig"))
      |> expect("errol" |> by_test_id() |> to_have_count(0))
    end
  end

  @tag driver: :static
  test "Fluffy's attribute wins over PlaywrightEx's" do
    put_fluffy_config(test_id_attribute: "data-testid")
    put_playwright_ex_config(:test, test_id_attribute: "data-owl")

    :static
    |> session_for_html(@owlery, base_url: Server.base_url())
    |> expect("errol" |> by_test_id() |> to_have_text("Errol"))
    |> expect("hedwig" |> by_test_id() |> to_have_count(0))
  end

  # Not the client's VM-global `selectors.setTestIdAttribute`, which PlaywrightEx.Test sets from
  # its own config: `get_by_test_id`'s selector with Fluffy's attribute.
  @tag driver: :playwright
  test "Playwright builds get_by_test_id's selector from Fluffy's attribute" do
    put_fluffy_config(test_id_attribute: "data-owl")
    session = session_for_html(:playwright, @owlery, base_url: Server.base_url())
    frame = Session.page_state(session).frame

    assert unwrap_and_return(session, by_test_id("hedwig"), & &1) ==
             PlaywrightEx.Frame.locator(frame, LocatorUtils.get_by_test_id_selector("data-owl", "hedwig"))
  end

  # With only PlaywrightEx's attribute, the suite's default, as its own native `get_by_test_id`.
  @tag driver: :playwright
  test "Playwright's locator equals PlaywrightEx's native get_by_test_id without Fluffy's attribute" do
    session = session_for_html(:playwright, @owlery, base_url: Server.base_url())
    frame = Session.page_state(session).frame

    assert unwrap_and_return(session, by_test_id("errol"), & &1) == PlaywrightEx.Frame.get_by_test_id(frame, "errol")
  end
end
