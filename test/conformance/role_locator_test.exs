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
     [name: ~s(Say "hello"), exact: true], 1},
    {"nav landmark", "<nav>Menu</nav>", :navigation, [], 1},
    {"main landmark", "<main>Body</main>", :main, [], 1},
    {"aside landmark", "<aside>Note</aside>", :complementary, [], 1},
    {"search landmark", "<search>Find</search>", :search, [], 1},
    {"article", "<article>Story</article>", :article, [], 1},
    {"page header", "<header>Top</header>", :banner, [], 1},
    {"page footer", "<footer>End</footer>", :contentinfo, [], 1},
    {"header inside an article", "<article><header>Top</header></article>", :banner, [], 0},
    {"footer inside a region role", ~s(<div role="region"><footer>End</footer></div>), :contentinfo, [], 0},
    {"header inside a section with another role", ~s(<section role="group"><header>Top</header></section>), :banner, [],
     1},
    {"section without a name", "<section>Body</section>", :region, [], 0},
    {"section with aria-label", ~s(<section aria-label="Details">Body</section>), :region, [name: "Details", exact: true],
     1},
    {"section with aria-labelledby", ~s(<section aria-labelledby="t"><h2 id="t">Details</h2></section>), :region,
     [name: "Details", exact: true], 1},
    {"form without a name", "<form></form>", :form, [], 0},
    {"form with aria-label", ~s(<form aria-label="Sign in"></form>), :form, [name: "Sign in", exact: true], 1},
    {"landmark not named by its content", "<nav>Menu</nav>", :navigation, [name: "Menu"], 0},
    {"explicit landmark not named by its content", ~s(<div role="navigation">Menu</div>), :navigation, [name: "Menu"], 0},
    {"landmark named by its title", ~s(<nav title="Site">Menu</nav>), :navigation, [name: "Site", exact: true], 1}
  ]

  for {case_name, html, role, options, expected} <- cases,
      driver <- [:static, :playwright] do
    @tag driver: driver
    test "matches #{case_name} by role with #{driver}" do
      session =
        session_for_html(unquote(driver), unquote(html), base_url: Fluffy.TestServer.base_url())

      expect(session, unquote(role) |> by_role(unquote(options)) |> to_have_count(unquote(expected)))
    end
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "a header's sectioning ancestor counts outside the locator's scope with #{driver}" do
      html = ~s(<article><div id="inner"><header>Top</header></div></article>)
      session = session_for_html(unquote(driver), html, base_url: Fluffy.TestServer.base_url())

      expect(session, "#inner" |> by_css() |> by_role(:banner) |> to_have_count(0))
    end
  end
end
