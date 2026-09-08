defmodule Fluffy.Conformance.LabelLocatorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  cases = [
    {"an explicit for/id label", ~s(<label for="email">Email address</label><input id="email">), "Email address", [], 1},
    {"a wrapping label", "<label>Display name <input></label>", "Display name", [], 1},
    {"a wrapping label containing nested text", "<label><span>Account</span> <strong>name</strong> <input></label>",
     "Account name", [exact: true], 1},
    {"a wrapping label with a hidden checkbox fallback",
     ~s(<label><input name="enabled" type="hidden" value=""><input name="enabled" type="checkbox" value="true">Daily</label>),
     "Daily", [exact: true], 1},
    {"either of multiple labels for one control",
     ~s(<label for="email">Work</label><label for="email">Email</label><input id="email">), "Work", [exact: true], 1},
    {"an aria-label", ~s(<input aria-label="Search site">), "Search", [], 1},
    {"a single aria-labelledby reference",
     ~s(<span id="account-name">Account name</span><input aria-labelledby="account-name">), "Account name", [exact: true],
     1},
    {"case-sensitive exact matching", ~s(<label for="city">City</label><input id="city">), "city", [exact: true], 0},
    {"quotes in a label", ~s(<label for="quote">Say &quot;hello&quot;</label><input id="quote">), ~s(Say "hello"),
     [exact: true], 1}
  ]

  for {case_name, html, label, options, expected} <- cases,
      driver <- [:static, :playwright] do
    @tag driver: driver
    test "finds a control from #{case_name} with #{driver}" do
      session =
        session_for_html(unquote(driver), unquote(html), base_url: Fluffy.TestServer.base_url())

      expect(session, count(by_label(unquote(label), unquote(options)), unquote(expected)))
    end
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "uses accessible-name precedence for labelled controls with #{driver}" do
      html = """
      <label for="search">HTML Search</label>
      <span id="aria-name">ARIA Labelled Search</span>
      <input id="search" aria-label="ARIA Search" aria-labelledby="aria-name">
      """

      session =
        session_for_html(unquote(driver), html, base_url: Fluffy.TestServer.base_url())

      session
      |> expect(count(by_label("ARIA Labelled Search", exact: true), 1))
      |> expect(count(by_label("ARIA Search", exact: true), 0))
      |> expect(count(by_label("HTML Search", exact: true), 0))
    end

    @tag driver: driver
    test "matches each aria-labelledby reference rather than a combined label with #{driver}" do
      html = """
      <span id="first">Billing</span>
      <span id="second">address</span>
      <input aria-labelledby="first second">
      """

      session =
        session_for_html(unquote(driver), html, base_url: Fluffy.TestServer.base_url())

      session
      |> expect(count(by_label("Billing", exact: true), 1))
      |> expect(count(by_label("address", exact: true), 1))
      |> expect(count(by_label("Billing address", exact: true), 0))
    end
  end
end
