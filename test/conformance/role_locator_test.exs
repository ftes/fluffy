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
    {"landmark named by its title", ~s(<nav title="Site">Menu</nav>), :navigation, [name: "Site", exact: true], 1},
    {"invalid explicit role keeps the implicit one", ~s(<nav role="foo">Menu</nav>), :navigation, [], 1},
    {"invalid explicit role on a header", ~s(<header role="foo">Top</header>), :banner, [], 1},
    {"uppercase explicit role", ~s(<div role="NAVIGATION">Menu</div>), :navigation, [], 1},
    {"first valid role token", ~s(<div role="foo button">Go</div>), :button, [], 1},
    {"role none with a global aria attribute", ~s(<nav role="none" aria-label="x">Menu</nav>), :navigation, [], 1},
    {"role presentation with a global aria attribute", ~s(<h2 role="presentation" aria-label="x">T</h2>), :heading, [],
     1},
    {"focusable button with role none", ~s(<button role="none">Go</button>), :button, [], 1},
    {"link with role none", ~s(<a href="/x" role="none">Go</a>), :link, [], 1},
    {"tabindex with role none", ~s(<h2 role="none" tabindex="0">T</h2>), :heading, [], 1},
    {"disabled button with role none", ~s(<button role="none" disabled>Go</button>), :button, [], 0},
    {"disabled fieldset button with role none", ~s(<fieldset disabled><button role="none">Go</button></fieldset>),
     :button, [], 0},
    {"role presentation on a named focusable section",
     ~s(<section role="presentation" aria-label="X" tabindex="0">Body</section>), :region, [], 1},
    {"role presentation on a named form", ~s(<form role="presentation" aria-label="X"></form>), :form, [], 1},
    {"first valid role token after a bogus one", ~s(<div role="bogus navigation">Menu</div>), :navigation, [], 1},
    {"role none without a conflict", ~s(<h2 role="none">T</h2>), :none, [], 1},
    {"role presentation without a conflict", ~s(<h2 role="presentation">T</h2>), :presentation, [], 1},
    {"list items inherit presentation", ~s(<ul role="none"><li>One</li></ul>), :listitem, [], 0},
    {"table cells inherit presentation", ~s(<table role="presentation"><tr><td>A</td></tr></table>), :cell, [], 0},
    {"table rows inherit presentation", ~s(<table role="presentation"><tr><td>A</td></tr></table>), :row, [], 0},
    {"a conflict stops presentation inheritance", ~s(<ul role="none" aria-label="x"><li>One</li></ul>), :listitem, [], 1},
    {"aria-label is prohibited on presentation when inherited",
     ~s(<ul role="presentation" aria-label="x"><li>One</li></ul>), :listitem, [], 0},
    {"blank aria-label falls through to content", ~s(<button aria-label="  ">Save</button>), :button,
     [name: "Save", exact: true], 1},
    {"blank aria-label falls through to title", ~s(<button aria-label="  " title="Hint"></button>), :button,
     [name: "Hint", exact: true], 1},
    {"empty aria-label on a landmark falls through to title", ~s(<nav aria-label="" title="Site">Menu</nav>), :navigation,
     [name: "Site", exact: true], 1},
    {"dangling aria-labelledby falls through to title", ~s(<nav aria-labelledby="missing" title="Site"></nav>),
     :navigation, [name: "Site", exact: true], 1},
    {"dangling aria-labelledby falls through to a label",
     ~s(<label for="e">Email</label><input id="e" aria-labelledby="missing">), :textbox, [name: "Email", exact: true], 1},
    {"empty aria-labelledby target falls through to aria-label",
     ~s(<span id="e"></span><button aria-labelledby="e" aria-label="Save"></button>), :button,
     [name: "Save", exact: true], 1},
    {"dangling aria-labelledby on a section falls through to title",
     ~s(<section aria-labelledby="missing" title="Site"></section>), :region, [name: "Site", exact: true], 1},
    {"dangling aria-labelledby falls through to aria-label", ~s(<nav aria-labelledby="missing" aria-label="Site"></nav>),
     :navigation, [name: "Site", exact: true], 1},
    {"fieldset with a landmark role named by its legend", ~s(<fieldset role="search"><legend>Find</legend></fieldset>),
     :search, [name: "Find", exact: true], 1},
    {"fieldset with role region named by its legend", ~s(<fieldset role="region"><legend>Find</legend></fieldset>),
     :region, [name: "Find", exact: true], 1},
    {"table with role region named by its caption", ~s(<table role="region"><caption>Find</caption></table>), :region,
     [name: "Find", exact: true], 1},
    {"figure with role region named by its caption", ~s(<figure role="region"><figcaption>Find</figcaption></figure>),
     :region, [name: "Find", exact: true], 1},
    {"explicit dialog not named by its content", ~s(<div role="dialog">Foo</div>), :dialog, [name: "Foo"], 0},
    {"resolved aria-labelledby skips the native label",
     ~s(<span id="e"></span><label for="i">Label</label><input id="i" aria-labelledby="e" title="Hint">), :textbox,
     [name: "Hint", exact: true], 1},
    {"link content does not pass through an article", ~s(<a href="/x"><article>Story</article></a>), :link,
     [name: "Story"], 0},
    {"button content does not pass through a nav", ~s(<button><nav>Menu</nav></button>), :button, [name: "Menu"], 0},
    {"button content passes through a generic element", ~s(<button><div>Menu</div></button>), :button,
     [name: "Menu", exact: true], 1},
    {"link content passes through lists", ~s(<a href="/x"><ul><li>One</li></ul></a>), :link, [name: "One", exact: true],
     1},
    {"a landmark descendant contributes its title", ~s(<a href="/x"><nav title="Site">Menu</nav></a>), :link,
     [name: "Site", exact: true], 1},
    {"a descendant's aria-label replaces its content", ~s(<a href="/x"><span aria-label="Inner">x</span></a>), :link,
     [name: "Inner", exact: true], 1},
    {"a descendant image contributes its alt", ~s(<button><img alt="Logo"></button>), :button,
     [name: "Logo", exact: true], 1},
    {"block children are separated in a name", ~s(<button><div>One</div><div>Two</div></button>), :button,
     [name: "One Two", exact: true], 1},
    {"ruby text is separated in a name", ~s(<button><ruby>A<rt>b</rt></ruby></button>), :button,
     [name: "A b", exact: true], 1},
    {"svg metadata stays out of a name", ~s(<button><svg><desc>D</desc></svg>Go</button>), :button,
     [name: "Go", exact: true], 1},
    {"cells are separated in a row name", ~s(<table><tr><td>A</td><td>B</td></tr></table>), :row,
     [name: "A B", exact: true], 1},
    {"list not named by its content", "<ul><li>One</li></ul>", :list, [name: "One"], 0},
    {"list item not named by its content", "<ul><li>One</li></ul>", :listitem, [name: "One"], 0},
    {"table not named by its content", "<table><tr><td>A</td></tr></table>", :table, [name: "A"], 0},
    {"cell named by its content", "<table><tr><td>A</td></tr></table>", :cell, [name: "A", exact: true], 1},
    {"table named by its caption", "<table><caption>Pets</caption><tr><td>A</td></tr></table>", :table,
     [name: "Pets", exact: true], 1},
    {"naming prohibited on a paragraph", ~s(<p aria-label="x">Intro</p>), :paragraph, [name: "x"], 0},
    {"fieldset named by its legend", "<fieldset><legend>Pets</legend></fieldset>", :group, [name: "Pets", exact: true],
     1},
    {"figure named by its caption", "<figure><figcaption>Pets</figcaption></figure>", :figure,
     [name: "Pets", exact: true], 1},
    {"svg named by its title", "<svg><title>Logo</title></svg>", :img, [name: "Logo", exact: true], 1},
    {"textbox named by its placeholder", ~s(<input placeholder="Search">), :textbox, [name: "Search", exact: true], 1},
    {"image with an empty alt", ~s(<img alt="">), :presentation, [], 1},
    {"image with an empty alt and a title", ~s(<img alt="" title="Logo">), :img, [name: "Logo", exact: true], 1},
    {"search input", ~s(<input type="search">), :searchbox, [], 1},
    {"password input", ~s(<input type="password">), :textbox, [], 1},
    {"file input", ~s(<input type="file">), :button, [], 1},
    {"input with a datalist", ~s(<input list="l"><datalist id="l"></datalist>), :combobox, [], 1},
    {"hidden datalist", "<datalist></datalist>", :listbox, [], 0},
    # Phoenix locators do not model `details` and `dialog` open state.
    {"a name referenced through closed details",
     ~s(<span id="l"><details><summary>S</summary><p>B</p></details></span><input aria-labelledby="l">), :textbox,
     [name: "S B", exact: true], %{static: 1, playwright: 0}},
    {"a name referenced through a closed dialog", ~s(<span id="l"><dialog>D</dialog>Go</span><input aria-labelledby="l">),
     :textbox, [name: "D Go", exact: true], %{static: 1, playwright: 0}},
    {"link in a closed details menu",
     ~s(<details><summary>Menu</summary><ul><li><a href="/x">Out</a></li></ul></details>), :link, [name: "Out"],
     %{static: 1, playwright: 0}},
    {"link in an open details menu",
     ~s(<details open><summary>Menu</summary><ul><li><a href="/x">Out</a></li></ul></details>), :link, [name: "Out"], 1},
    {"open dialog", "<dialog open>Hi</dialog>", :dialog, [], 1},
    {"closed dialog", "<dialog>Hi</dialog>", :dialog, [], %{static: 1, playwright: 0}},
    {"details", "<details><summary>More</summary></details>", :group, [], 1},
    {"content of closed details", "<details><summary>More</summary><p>Body</p></details>", :paragraph, [],
     %{static: 1, playwright: 0}},
    {"content of open details", "<details open><summary>More</summary><p>Body</p></details>", :paragraph, [], 1},
    {"open dialog in closed details", "<details><summary>More</summary><dialog open>Hi</dialog></details>", :dialog, [],
     %{static: 1, playwright: 0}},
    {"optgroup of a dropdown", ~s(<select><optgroup label="Pets"></optgroup></select>), :group, [], 0},
    {"optgroup of a list box", ~s(<select size="3"><optgroup label="Pets"></optgroup></select>), :group, [], 1},
    {"area", ~s(<map name="m"><area href="/x" alt="x"></map>), :link, [], 0},
    {"data cell in a grid", ~s(<table role="grid"><tr><td>A</td></tr></table>), :gridcell, [], 1},
    {"header cell next to a data cell", "<table><tr><th>H</th><td>1</td></tr></table>", :rowheader, [], 1},
    {"header cell among header cells", "<table><tr><th>H</th><th>I</th><th>J</th></tr></table>", :columnheader, [], 3},
    {"only header cell of a single row", "<table><tr><th>H</th></tr></table>", :columnheader, [], 0},
    # Phoenix locators do not model `details` open state for text either.
    {"direct text of closed details in a referenced name",
     ~s(<span id="l"><details><summary>S</summary>More</details></span><input aria-labelledby="l">), :textbox,
     [name: "S More", exact: true], %{static: 1, playwright: 0}},
    {"closed details text dropped from a Playwright name",
     ~s(<span id="l"><details><summary>S</summary>More</details></span><input aria-labelledby="l">), :textbox,
     [name: "S", exact: true], %{static: 0, playwright: 1}},
    # Phoenix locators do not model `popover` open state.
    {"content of a closed popover", ~s(<div popover><button>Go</button></div>), :button, [], %{static: 1, playwright: 0}},
    {"hidden svg stays inline in a name", ~s(<button>A<svg hidden></svg>B</button>), :button, [name: "AB", exact: true],
     1},
    {"hidden element separates a name", ~s(<button>A<span hidden></span>B</button>), :button, [name: "A B", exact: true],
     1},
    {"blank tabindex counts as zero", ~s(<h2 role="none" tabindex="">T</h2>), :heading, [], 1},
    {"lowercase infinity tabindex", ~s(<h2 role="none" tabindex="infinity">T</h2>), :heading, [], 0},
    {"uppercase infinity tabindex on an image", ~s(<img alt="" tabindex="INFINITY">), :presentation, [], 1},
    {"nested disabled fieldset legend button",
     ~s(<fieldset disabled><fieldset disabled><legend><button role="none">Go</button></legend></fieldset></fieldset>),
     :button, [], 1},
    {"embedded textbox value in a name", ~s(<span id="l">Qty <input value="3"></span><input aria-labelledby="l">),
     :textbox, [name: "Qty 3", exact: true], 1},
    {"embedded textarea value in a name", ~s(<span id="l">Note <textarea>Hi</textarea></span><input aria-labelledby="l">),
     :textbox, [name: "Note Hi", exact: true], 1},
    {"embedded role textbox text in a name",
     ~s(<span id="l">Note <span role="textbox">Hi</span></span><input aria-labelledby="l">), :textbox,
     [name: "Note Hi", exact: true], 1},
    {"embedded select's selected option in a name",
     ~s(<span id="l">Pick <select><option>A</option><option selected>B</option></select></span><input aria-labelledby="l">),
     :textbox, [name: "Pick B", exact: true], 1},
    {"embedded select's first enabled option in a name",
     ~s(<span id="l">Pick <select><option disabled>A</option><option>B</option></select></span><input aria-labelledby="l">),
     :textbox, [name: "Pick B", exact: true], 1},
    {"embedded multi-select options in a name",
     ~s(<span id="l">Pick <select multiple><option selected>A</option><option>B</option><option selected>C</option></select></span><input aria-labelledby="l">),
     :textbox, [name: "Pick A C", exact: true], 1},
    {"embedded list box without a selection in a name",
     ~s(<span id="l">Pick <select size="2"><option>A</option><option>B</option></select></span><input aria-labelledby="l">),
     :textbox, [name: "Pick A", exact: true], 1},
    {"embedded aria combobox option in a name",
     ~s(<span id="l">Pick <span role="combobox" aria-owns="b"></span></span><ul id="b" role="listbox"><li role="option" aria-selected="true">A</li><li role="option">B</li></ul><input aria-labelledby="l">),
     :textbox, [name: "Pick A", exact: true], 1},
    {"embedded aria listbox option in a name",
     ~s(<span id="l">Pick <ul role="listbox"><li role="option" aria-selected="TRUE">A</li><li role="option">B</li></ul></span><input aria-labelledby="l">),
     :textbox, [name: "Pick A", exact: true], 1},
    {"embedded input combobox value in a name",
     ~s(<span id="l">Pick <input list="d" value="V"></span><datalist id="d"></datalist><input aria-labelledby="l">),
     :textbox, [name: "Pick V", exact: true], 1},
    {"embedded slider value in a name",
     ~s(<span id="l">Vol <input type="range" value="5"></span><input aria-labelledby="l">), :textbox,
     [name: "Vol 5", exact: true], 1},
    {"embedded spinbutton value in a name",
     ~s(<span id="l">Qty <input type="number" value="2"></span><input aria-labelledby="l">), :textbox,
     [name: "Qty 2", exact: true], 1},
    {"embedded progress value in a name",
     ~s(<span id="l">Done <progress value="1" max="2"></progress></span><input aria-labelledby="l">), :textbox,
     [name: "Done 1", exact: true], 1},
    {"embedded slider aria-valuetext in a name",
     ~s(<span id="l">Vol <span role="slider" aria-valuetext="High" aria-valuenow="5"></span></span><input aria-labelledby="l">),
     :textbox, [name: "Vol High", exact: true], 1},
    {"embedded slider aria-valuenow in a name",
     ~s(<span id="l">Vol <span role="slider" aria-valuenow="5" value="1"></span></span><input aria-labelledby="l">),
     :textbox, [name: "Vol 5", exact: true], 1},
    {"embedded menu contributes nothing to a name",
     ~s(<span id="l">Go <span role="menu">x</span></span><input aria-labelledby="l">), :textbox,
     [name: "Go", exact: true], 1},
    {"embedded value in a label", ~s(<label>Qty <input value="3"><select id="c"></select></label>), :textbox,
     [name: "Qty", exact: true], 1},
    {"embedded value in a button's content", ~s(<button>Qty <input value="3"></button>), :button,
     [name: "Qty 3", exact: true], 1},
    {"aria-owns extends a name", ~s(<button aria-owns="o">A</button><span id="o">B</span>), :button,
     [name: "AB", exact: true], 1},
    {"aria-owns names an empty element", ~s(<a href="/x" aria-owns="o"></a><span id="o">B</span>), :link,
     [name: "B", exact: true], 1},
    {"aria-owns separates non-inline targets", ~s(<button aria-owns="o">A</button><div id="o">B</div>), :button,
     [name: "A B", exact: true], 1},
    {"aria-owns follows reference order",
     ~s(<button aria-owns="y x">A</button><span id="x">X</span><span id="y">Y</span>), :button,
     [name: "AYX", exact: true], 1},
    {"aria-owns skips a hidden target", ~s(<button aria-owns="o">A</button><span id="o" hidden>B</span>), :button,
     [name: "A", exact: true], 1},
    {"aria-owns ignores a dangling reference", ~s(<button aria-owns="missing">A</button>), :button,
     [name: "A", exact: true], 1},
    {"aria-owns on itself does not loop", ~s(<button id="b" aria-owns="b">A</button>), :button, [name: "A", exact: true],
     1},
    {"aria-owns in a referenced name",
     ~s(<span id="l" aria-owns="o">A</span><span id="o">B</span><input aria-labelledby="l">), :textbox,
     [name: "AB", exact: true], 1},
    {"embedded select in a disabled fieldset skips only its own disabled options",
     ~s(<fieldset disabled><span id="l">Pick <select><option disabled>A</option><option>B</option></select></span></fieldset><input aria-labelledby="l">),
     :textbox, [name: "Pick B", exact: true], 1},
    {"embedded select skips a disabled optgroup",
     ~s(<span id="l">Pick <select><optgroup disabled><option>A</option></optgroup><option>B</option></select></span><input aria-labelledby="l">),
     :textbox, [name: "Pick B", exact: true], 1},
    {"audio without controls separates a name", ~s(<button>A<audio></audio>B</button>), :button,
     [name: "A B", exact: true], 1},
    {"a label's noscript control is not its control", ~s(<label>Pick <noscript><input></noscript><input></label>),
     :textbox, [name: "Pick", exact: true], 1},
    {"an empty for matches no empty id", ~s(<label for="">Pick</label><input id="">), :textbox, [name: "Pick"], 0},
    {"hr in a dropdown", ~s(<select><hr></select>), :separator, [], 0},
    {"hr outside a select", "<hr>", :separator, [], 1},
    {"image input named by alt", ~s(<input type="image" alt="Go" title="T">), :button, [name: "Go", exact: true], 1},
    {"image input named by title", ~s(<input type="image" alt="  " title="T">), :button, [name: "T", exact: true], 1},
    {"image input default name", ~s(<input type="image">), :button, [name: "Submit", exact: true], 1},
    {"image input named by a label", ~s(<label>Send <input type="image" alt="Go"></label>), :button,
     [name: "Send", exact: true], 1},
    {"reset input default name", ~s(<input type="reset">), :button, [name: "Reset", exact: true], 1},
    {"reset input named by value", ~s(<input type="reset" value="Clear">), :button, [name: "Clear", exact: true], 1},
    {"reset input with a blank value", ~s(<input type="reset" value="  " title="T">), :button,
     [name: "Reset", exact: true], 1}
  ]

  implicit_roles = [
    {"<article>x</article>", :article},
    {"<blockquote>x</blockquote>", :blockquote},
    {"<code>x</code>", :code},
    {"<dl><dt>x</dt><dd>y</dd></dl>", :term},
    {"<dl><dt>x</dt><dd>y</dd></dl>", :definition},
    {"<del>x</del>", :deletion},
    {"<dfn>x</dfn>", :term},
    {"<em>x</em>", :emphasis},
    {"<hr>", :separator},
    {"<ins>x</ins>", :insertion},
    {"<mark>x</mark>", :mark},
    {"<math></math>", :math},
    {"<menu><li>x</li></menu>", :list},
    {"<meter></meter>", :meter},
    {"<output></output>", :status},
    {"<p>x</p>", :paragraph},
    {"<progress></progress>", :progressbar},
    {"<strong>x</strong>", :strong},
    {"<sub>x</sub>", :subscript},
    {"<sup>x</sup>", :superscript},
    {"<svg></svg>", :img},
    {"<table><caption>x</caption></table>", :caption},
    {"<time>x</time>", :time}
  ]

  cases =
    cases ++
      Enum.map(implicit_roles, fn {html, role} -> {"implicit role #{role} of #{html}", html, role, [], 1} end)

  for {case_name, html, role, options, expected} <- cases,
      driver <- [:static, :playwright] do
    count = if is_map(expected), do: Map.fetch!(expected, driver), else: expected

    @tag driver: driver
    test "matches #{case_name} by role with #{driver}" do
      session =
        session_for_html(unquote(driver), unquote(html), base_url: Fluffy.TestServer.base_url())

      expect(session, unquote(role) |> by_role(unquote(options)) |> to_have_count(unquote(count)))
    end
  end

  scoped_cases = [
    {"a header's sectioning ancestor", ~s(<article><div id="inner"><header>Top</header></div></article>), :banner, [], 0},
    {"an aria-labelledby target", ~s(<span id="t">Pay</span><div id="inner"><button aria-labelledby="t"></button></div>),
     :button, [name: "Pay", exact: true], 1},
    {"an aria-labelledby target of a landmark",
     ~s(<h2 id="t">Details</h2><div id="inner"><section aria-labelledby="t"></section></div>), :region,
     [name: "Details", exact: true], 1},
    {"a label", ~s(<label for="i">Email</label><div id="inner"><input id="i"></div>), :textbox,
     [name: "Email", exact: true], 1},
    {"a hidden ancestor of a landmark", ~s(<div hidden><div id="inner"><nav>Menu</nav></div></div>), :navigation, [], 0},
    {"a hidden ancestor", ~s(<div hidden><div id="inner"><button>Go</button></div></div>), :button, [], 0},
    {"an aria-hidden ancestor", ~s(<div aria-hidden="true"><div id="inner"><button>Go</button></div></div>), :button, [],
     0},
    {"presentation inherited from the scope", ~s(<ul id="inner" role="none"><li>One</li></ul>), :listitem, [], 0},
    {"a presentational ancestor", ~s(<ul role="none"><div id="inner"><li>One</li></div></ul>), :listitem, [], 1},
    {"the scope itself never matching", ~s(<nav id="inner">Menu</nav>), :navigation, [], 0}
  ]

  for {case_name, html, role, options, expected} <- scoped_cases,
      driver <- [:static, :playwright] do
    @tag driver: driver
    test "#{case_name} counts across the locator's scope with #{driver}" do
      session = session_for_html(unquote(driver), unquote(html), base_url: Fluffy.TestServer.base_url())

      expect(
        session,
        "#inner" |> by_css() |> by_role(unquote(role), unquote(options)) |> to_have_count(unquote(expected))
      )
    end
  end

  # Both checks share the rendered rule; `aria-hidden` only affects role matching.
  visibility_cases = [
    {"plain text", "<p id=t>Hi</p>", true},
    {"aria-hidden element", ~s(<p id="t" aria-hidden="true">Hi</p>), true},
    {"aria-hidden ancestor", ~s(<div aria-hidden="true"><p id="t">Hi</p></div>), true},
    {"hidden attribute", ~s(<p id="t" hidden>Hi</p>), false},
    {"hidden ancestor", ~s(<div hidden><p id="t">Hi</p></div>), false},
    {"hidden input", ~s(<input id="t" type="hidden">), false},
    {"uppercase hidden input", ~s(<input id="t" type="HIDDEN">), false},
    {"script", ~s(<script id="t">1</script>), false},
    {"style", ~s(<style id="t">p {}</style>), false},
    {"template", ~s(<template id="t"><p>Hi</p></template>), false},
    {"noscript", ~s(<noscript id="t">Hi</noscript>), false},
    {"datalist", ~s(<datalist id="t"><option>A</option></datalist>), false},
    {"audio without controls", ~s(<audio id="t"></audio>), false},
    {"video fallback", ~s(<video><p id="t">Hi</p></video>), false},
    {"progress fallback", ~s(<progress><b id="t">Hi</b></progress>), false},
    {"svg desc", ~s(<svg><desc id="t">Hi</desc></svg>), false},
    {"hr in a dropdown", ~s(<select><hr id="t"></select>), false},
    {"option of a list box", ~s(<select size="3"><option id="t">A</option></select>), true},
    {"optgroup of a dropdown", ~s(<select><optgroup id="t" label="A"></optgroup></select>), false},
    {"optgroup of a list box", ~s(<select size="3"><optgroup id="t" label="A"><option>A</option></optgroup></select>),
     true}
  ]

  # Phoenix locators do not model these open states.
  visibility_cases =
    visibility_cases ++
      [
        {"content of closed details", ~s(<details><summary>S</summary><p id="t">Hi</p></details>),
         %{static: true, playwright: false}},
        {"closed dialog", ~s(<dialog id="t">Hi</dialog>), %{static: true, playwright: false}},
        {"closed popover", ~s(<div id="t" popover>Hi</div>), %{static: true, playwright: false}},
        {"option of a closed dropdown", ~s(<select><option id="t">A</option></select>),
         %{static: true, playwright: false}}
      ]

  for {case_name, html, expected} <- visibility_cases, driver <- [:static, :playwright] do
    visible? = if is_map(expected), do: Map.fetch!(expected, driver), else: expected

    @tag driver: driver
    test "#{case_name} is #{if visible?, do: "visible", else: "not visible"} with #{driver}" do
      session = session_for_html(unquote(driver), unquote(html), base_url: Fluffy.TestServer.base_url())
      target = by_css("#t")

      if unquote(visible?) do
        session
        |> expect(to_be_visible(target))
        |> expect(target |> filter(visible: true) |> to_have_count(1))
        |> expect(target |> filter(visible: false) |> to_have_count(0))
      else
        session
        |> expect(to_be_hidden(target))
        |> expect(target |> filter(visible: true) |> to_have_count(0))
        |> expect(target |> filter(visible: false) |> to_have_count(1))
      end
    end
  end

  for driver <- [:static, :playwright] do
    @tag driver: driver
    test "aria-hidden hides an element from by_role but not from visibility with #{driver}" do
      session =
        session_for_html(unquote(driver), ~s(<button aria-hidden="true">Go</button>),
          base_url: Fluffy.TestServer.base_url()
        )

      session
      |> expect(:button |> by_role() |> to_have_count(0))
      |> expect("button" |> by_css() |> to_be_visible())
    end

    @tag driver: driver
    test "inert content does not shift role matches with #{driver}" do
      html =
        ~s(<div id="s"><noscript><a href="/n">N</a></noscript><svg><template><a href="/t">T</a></template></svg><a href="/after">After</a></div>)

      session = session_for_html(unquote(driver), html, base_url: Fluffy.TestServer.base_url())

      session
      |> expect(:link |> by_role(name: "After") |> to_have_attribute("href", "/after"))
      |> expect("#s" |> by_css() |> by_role(:link, name: "After") |> to_have_attribute("href", "/after"))
    end

    @tag driver: driver
    test "a role filter sees names outside the candidate with #{driver}" do
      html = ~s(<span id="t">Pay</span><div class="c"><button aria-labelledby="t"></button></div><div class="c"></div>)
      session = session_for_html(unquote(driver), html, base_url: Fluffy.TestServer.base_url())
      button = by_role(:button, name: "Pay", exact: true)

      expect(session, ".c" |> by_css() |> filter(has: button) |> to_have_count(1))
    end

    @tag driver: driver
    test "overlapping scopes match an element once with #{driver}" do
      html = ~s(<div class="s"><div class="s"><button>Go</button></div></div>)
      session = session_for_html(unquote(driver), html, base_url: Fluffy.TestServer.base_url())

      expect(session, ".s" |> by_css() |> by_role(:button) |> to_have_count(1))
    end
  end
end
