defmodule Fluffy.Conformance.TestIdAttributeTest do
  # Playwright Test's `testIdAttribute`, `config :playwright_ex, :test, test_id_attribute:`, is
  # global config.
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright, only: [unwrap_and_return: 3]

  alias Fluffy.Session
  alias Fluffy.Support.Server

  @owlery ~s(<section id="owlery"><p data-owl="hedwig">Hedwig</p><p data-testid="errol">Errol</p></section>)

  @tag driver: :static
  test "Phoenix matches the configured attribute" do
    put_playwright_ex_config(:test, test_id_attribute: "data-owl")

    :static
    |> session_for_html(@owlery)
    |> expect("hedwig" |> by_test_id() |> to_have_text("Hedwig"))
    |> expect("errol" |> by_test_id() |> to_have_count(0))
    |> expect("#owlery" |> by_css() |> by_test_id("hedwig") |> to_have_count(1))
  end

  # As upstream's test id engine, a comma-separated list matches any of its attributes.
  @tag driver: :static
  test "Phoenix matches any attribute of a comma-separated list" do
    put_playwright_ex_config(:test, test_id_attribute: "data-owl,data-testid")

    :static
    |> session_for_html(@owlery)
    |> expect("hedwig" |> by_test_id() |> to_have_text("Hedwig"))
    |> expect("errol" |> by_test_id() |> to_have_text("Errol"))
  end

  # The client's `selectors.setTestIdAttribute`, which PlaywrightEx.Test sets on each pooled
  # driver from the same config, applies: the native locator is PlaywrightEx's `get_by_test_id`.
  @tag driver: :playwright
  test "Playwright builds PlaywrightEx's get_by_test_id" do
    session = session_for_html(:playwright, @owlery, base_url: Server.base_url())
    frame = Session.page_state(session).frame

    assert unwrap_and_return(session, by_test_id("errol"), & &1) == PlaywrightEx.Frame.get_by_test_id(frame, "errol")
  end
end
