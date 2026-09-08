defmodule Fluffy.Conformance.AttributeLocatorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  cases = [
    {"placeholder substring", ~s(<input placeholder="Work Email">), {:placeholder, "email", []}, 1},
    {"placeholder exact", ~s(<input placeholder="Work Email">), {:placeholder, "Work Email", [exact: true]}, 1},
    {"placeholder exact case", ~s(<input placeholder="Work Email">), {:placeholder, "work email", [exact: true]}, 0},
    {"attribute matching does not normalize whitespace", ~s(<input placeholder="Work   Email">),
     {:placeholder, "Work Email", []}, 0},
    {"alt text", ~s(<img alt="Fluffy logo">), {:alt_text, "LOGO", []}, 1},
    {"title", ~s(<abbr title="Application programming interface">API</abbr>), {:title, "programming", []}, 1},
    {"test id exact", ~s(<article data-testid="account-row"></article>), {:test_id, "account-row", []}, 1},
    {"test id does not use substring", ~s(<article data-testid="account-row"></article>), {:test_id, "account", []}, 0},
    {"custom test id attribute", ~s(<article data-qa="account-row"></article>),
     {:test_id, "account-row", [attribute: "data-qa"]}, 1}
  ]

  for {case_name, html, locator_spec, expected} <- cases,
      driver <- [:static, :playwright] do
    @tag driver: driver
    test "matches #{case_name} with #{driver}" do
      session =
        session_for_html(unquote(driver), unquote(html), base_url: Fluffy.TestServer.base_url())

      locator =
        case unquote(Macro.escape(locator_spec)) do
          {:placeholder, value, options} -> by_placeholder(value, options)
          {:alt_text, value, options} -> by_alt_text(value, options)
          {:title, value, options} -> by_title(value, options)
          {:test_id, value, options} -> by_test_id(value, options)
        end

      expect(session, count(locator, unquote(expected)))
    end
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "attribute locators stay inside their parent with #{driver}" do
      session =
        session_for_html(
          unquote(driver),
          ~s(<section class="wanted"><input placeholder="Email"></section><input placeholder="Email">),
          base_url: Fluffy.TestServer.base_url()
        )

      expect(session, count(by_placeholder(by_css(".wanted"), "Email", exact: true), 1))
    end
  end
end
