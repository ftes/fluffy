defmodule Fluffy.Conformance.AttributeLocatorTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.Server

  cases = [
    {"placeholder substring", ~s(<input placeholder="Work Email">), {:placeholder, "email", []}, 1},
    {"placeholder exact", ~s(<input placeholder="Work Email">), {:placeholder, "Work Email", [exact: true]}, 1},
    {"placeholder exact case", ~s(<input placeholder="Work Email">), {:placeholder, "work email", [exact: true]}, 0},
    {"attribute matching does not normalize whitespace", ~s(<input placeholder="Work   Email">),
     {:placeholder, "Work Email", []}, 0},
    {"alt text", ~s(<img alt="Fluffy logo">), {:alt_text, "LOGO", []}, 1},
    {"title", ~s(<abbr title="Application programming interface">API</abbr>), {:title, "programming", []}, 1},
    {"test id exact", ~s(<article data-testid="vault-row"></article>), {:test_id, "vault-row"}, 1},
    {"test id does not use substring", ~s(<article data-testid="vault-row"></article>), {:test_id, "vault"}, 0},
    {"test id only in the configured attribute", ~s(<article data-owl="hedwig"></article>), {:test_id, "hedwig"}, 0},
    {"another attribute with by_css", ~s(<article data-owl="hedwig"></article>), {:css, ~s([data-owl="hedwig"])}, 1}
  ]

  for {case_name, html, locator_spec, expected} <- cases,
      driver <- [:static, :playwright] do
    @tag driver: driver
    test "matches #{case_name} with #{driver}" do
      session =
        session_for_html(unquote(driver), unquote(html), base_url: Server.base_url())

      locator =
        case unquote(Macro.escape(locator_spec)) do
          {:placeholder, value, options} -> by_placeholder(value, options)
          {:alt_text, value, options} -> by_alt_text(value, options)
          {:title, value, options} -> by_title(value, options)
          {:test_id, value} -> by_test_id(value)
          {:css, css} -> by_css(css)
        end

      expect(session, to_have_count(locator, unquote(expected)))
    end
  end

  test "by_test_id takes no options, as Playwright's getByTestId" do
    assert_raise ArgumentError, ~r/by_test_id\/2 takes no options.*test_id_attribute.*by_css/, fn ->
      by_test_id("hedwig", attribute: "data-owl")
    end
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "attribute locators stay inside their parent with #{driver}" do
      session =
        session_for_html(
          unquote(driver),
          ~s(<section class="wanted"><input placeholder="Email"></section><input placeholder="Email">),
          base_url: Server.base_url()
        )

      expect(session, ".wanted" |> by_css() |> by_placeholder("Email", exact: true) |> to_have_count(1))
    end
  end
end
