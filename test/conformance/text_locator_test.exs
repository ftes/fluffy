defmodule Fluffy.Conformance.TextLocatorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  cases = [
    {"normalizes whitespace", "<p>Save\n   changes</p>", "Save changes", [], 1},
    {"matches substrings case-insensitively by default", "<p>Welcome Back</p>", "come back", [], 1},
    {"matches exact normalized text", "<p>Hello</p><p>Hello world</p>", "Hello", [exact: true], 1},
    {"keeps exact matching case-sensitive", "<p>Hello</p>", "hello", [exact: true], 0},
    {"selects the deepest matching descendant", "<div>Outer <span>Inner</span></div>", "Inner", [], 1},
    {"can match a parent including descendant text", "<div>Outer <span>Inner</span></div>", "Outer Inner", [exact: true],
     1},
    {"uses button input values as text", ~s(<input type="submit" value="Log in">), "Log in", [], 1},
    {"escapes quotes in selector values", "<p>Say &quot;hello&quot;</p>", ~s(Say "hello"), [exact: true], 1},
    {"escapes backslashes in selector values", ~S(<p>Use C:\temp</p>), ~S(Use C:\temp), [exact: true], 1}
  ]

  for {case_name, html, text, options, expected} <- cases,
      driver <- [:static, :playwright] do
    @tag driver: driver
    test "#{case_name} with #{driver}" do
      session =
        session_for_html(unquote(driver), unquote(html), base_url: Fluffy.TestServer.base_url())

      expect(session, count(by_text(unquote(text), unquote(options)), unquote(expected)))
    end
  end
end
