defmodule Fluffy.Conformance.RoleLocatorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  cases = [
    {"button contents", "<button>Save changes</button>", :button, [name: "Save"], 1},
    {"button input value", ~s(<input type="submit" value="Create account">), :button, [name: "Create"], 1},
    {"link with href", ~s(<a href="/docs">Docs</a><a>Draft</a>), :link, [name: "Docs"], 1},
    {"link after inert template contents",
     ~s(<template><a href="/wrong">Wrong</a></template><a href="/poll/form" type="button">Start the survey</a>), :link,
     [name: "Start the survey", exact: true], 1},
    {"heading", "<h2>Account overview</h2>", :heading, [name: "overview"], 1},
    {"presentational exclusion", ~s(<h2 role="presentation">Decorative</h2>), :heading, [], 0},
    {"labelled checkbox", ~s(<label for="terms">Accept terms</label><input id="terms" type="checkbox">), :checkbox,
     [name: "Accept terms", exact: true], 1},
    {"aria-labelled radio", ~s(<input type="radio" aria-label="Express delivery">), :radio, [name: "Express"], 1},
    {"wrapping-label textbox", "<label>Display name <input></label>", :textbox, [name: "Display name", exact: true], 1},
    {"textarea", "<textarea>Draft content</textarea>", :textbox, [], 1},
    {"labelled combobox", ~s(<label for="country">Country</label><select id="country"><option>DE</option></select>),
     :combobox, [name: "Country", exact: true], 1},
    {"image alt text", ~s(<img alt="Fluffy logo">), :img, [name: "logo"], 1},
    {"list and list items", "<ul><li>First</li><li>Second</li></ul>", :listitem, [], 2},
    {"explicit role override", ~s(<button role="switch" aria-label="Power">off</button>), :switch,
     [name: "Power", exact: true], 1},
    {"combined aria-labelledby name",
     ~s(<span id="first">Billing</span><span id="second">address</span><input aria-labelledby="first second">), :textbox,
     [name: "Billing address", exact: true], 1},
    {"aria-label precedence", ~s(<button aria-label="Remove item">Delete</button>), :button,
     [name: "Remove", exact: false], 1},
    {"case-sensitive exact name", "<button>Save</button>", :button, [name: "save", exact: true], 0},
    {"structurally hidden elements",
     ~s(<button hidden>One</button><button aria-hidden="true">Two</button><button>Three</button>), :button, [], 1},
    {"aria-hidden descendants omitted from an accessible name",
     ~s(<label>Visible <span aria-hidden="true">ignored</span><input></label>), :textbox, [name: "Visible", exact: true],
     1},
    {"invalid input types use the text state", ~s(<input type="check" aria-label="Fallback">), :textbox,
     [name: "Fallback", exact: true], 1},
    {"quotes in an accessible name", "<button>Say &quot;hello&quot;</button>", :button,
     [name: ~s(Say "hello"), exact: true], 1}
  ]

  for {case_name, html, role, options, expected} <- cases,
      driver <- [:static, :playwright] do
    @tag driver: driver
    test "matches #{case_name} by role with #{driver}" do
      session =
        session_for_html(unquote(driver), unquote(html), base_url: Fluffy.TestServer.base_url())

      expect(session, count(by_role(unquote(role), unquote(options)), unquote(expected)))
    end
  end
end
