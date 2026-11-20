defmodule Fluffy.Conformance.TestIdAttributeTest do
  # Playwright Test's `testIdAttribute` is global config, on every driver: the Phoenix drivers
  # read it, and each pooled Playwright driver gets it as it starts.
  use Fluffy.Support.Case, async: false

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator
  import Fluffy.Playwright, only: [unwrap_and_return: 3]

  alias Fluffy.Session
  alias Playwright.Test.BrowserPool

  @owlery ~s(<section id="owlery"><p data-owl="hedwig">Hedwig</p><p data-testid="errol">Errol</p></section>)

  for driver <- Drivers.html() do
    @tag driver: driver
    test "#{driver} matches the configured attribute", %{driver: driver} do
      put_test_id_attribute(driver, "data-owl")

      driver
      |> session_for_html(@owlery)
      |> expect("hedwig" |> by_test_id() |> to_have_text("Hedwig"))
      |> expect("errol" |> by_test_id() |> to_have_count(0))
      |> expect("#owlery" |> by_css() |> by_test_id("hedwig") |> to_have_count(1))
    end

    # As upstream's test id engine, a comma-separated list matches any of its attributes.
    @tag driver: driver
    test "#{driver} matches any attribute of a comma-separated list", %{driver: driver} do
      put_test_id_attribute(driver, "data-owl,data-testid")

      driver
      |> session_for_html(@owlery)
      |> expect("hedwig" |> by_test_id() |> to_have_text("Hedwig"))
      |> expect("errol" |> by_test_id() |> to_have_text("Errol"))
    end

    # A name is any CSS identifier, non-ASCII characters included.
    @tag driver: driver
    test "#{driver} matches a non-ASCII attribute", %{driver: driver} do
      put_test_id_attribute(driver, "data-élève,data-owl")

      driver
      |> session_for_html(~s(<p data-élève="hermione">Hermione</p>))
      |> expect("hermione" |> by_test_id() |> to_have_text("Hermione"))
    end

    # As upstream's `if (testIdAttribute)`, an empty one sets none: the default stays.
    @tag driver: driver
    test "#{driver} keeps the default attribute for an empty one", %{driver: driver} do
      put_test_id_attribute(driver, "")

      driver
      |> session_for_html(@owlery)
      |> expect("errol" |> by_test_id() |> to_have_text("Errol"))
      |> expect("hedwig" |> by_test_id() |> to_have_count(0))
    end
  end

  # As Playwright's own native `get_by_test_id`.
  @tag driver: :playwright
  test "Playwright's locator equals Playwright's native get_by_test_id" do
    session = session_for_html(:playwright, @owlery)
    frame = Session.page_state(session).frame

    assert unwrap_and_return(session, by_test_id("errol"), & &1) == Playwright.Frame.get_by_test_id(frame, "errol")
  end

  # A suite has one attribute. To switch it, set the config and, as upstream's own tests do,
  # the running driver's (`selectors.setTestIdAttribute`), restored after the test.
  defp put_test_id_attribute(driver, name) do
    suite = Playwright.Test.config().test_id_attribute
    put_playwright_config(:test, test_id_attribute: name)

    # The pool sets none for an empty one, so the running driver keeps the suite's.
    if driver == :playwright and name != "" do
      selectors = Playwright.selectors(BrowserPool.playwright(BrowserPool.browser()))
      :ok = Playwright.Selectors.set_test_id_attribute(selectors, name)
      on_exit(fn -> Playwright.Selectors.set_test_id_attribute(selectors, suite) end)
    end
  end
end
