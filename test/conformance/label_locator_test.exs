defmodule Fluffy.Conformance.LabelLocatorTest do
  use Fluffy.TestCase, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  cases = [
    {"an explicit for/id label", ~s(<label for="email">Email address</label><input id="email">), "Email address", [], 1},
    {"a wrapping label", "<label>Display name <input></label>", "Display name", [], 1},
    {"a wrapping label containing nested text", "<label><span>Vault</span> <strong>name</strong> <input></label>",
     "Vault name", [exact: true], 1},
    {"a wrapping label with a hidden checkbox fallback",
     ~s(<label><input name="enabled" type="hidden" value=""><input name="enabled" type="checkbox" value="true">Daily</label>),
     "Daily", [exact: true], 1},
    {"either of multiple labels for one control",
     ~s(<label for="email">Work</label><label for="email">Email</label><input id="email">), "Work", [exact: true], 1},
    {"an aria-label", ~s(<input aria-label="Search site">), "Search", [], 1},
    {"an aria-label on a link", ~s(<a href="/edit" aria-label="Edit schedule">Edit</a>), "Edit schedule", [exact: true],
     1},
    {"an aria-label on a non-control", ~s(<div aria-label="Details panel"></div>), "Details", [], 1},
    {"an aria-labelledby reference on a link",
     ~s(<span id="edit-label">Edit schedule</span><a href="/edit" aria-labelledby="edit-label">Edit</a>), "Edit schedule",
     [exact: true], 1},
    {"an HTML label pointing at a non-labelable link",
     ~s(<label for="edit">Edit schedule</label><a id="edit" href="/edit">Edit</a>), "Edit schedule", [exact: true], 0},
    {"a single aria-labelledby reference",
     ~s(<span id="vault-name">Vault name</span><input aria-labelledby="vault-name">), "Vault name", [exact: true], 1},
    {"case-sensitive exact matching", ~s(<label for="city">City</label><input id="city">), "city", [exact: true], 0},
    {"quotes in a label", ~s(<label for="quote">Say &quot;hello&quot;</label><input id="quote">), ~s(Say "hello"),
     [exact: true], 1},
    # The cases below follow upstream's getByLabel specs (selectors-get-by.spec.ts).
    {"a wrapping label's first labelable descendant", ~s(<label>Wand<button id="target">Cast</button><input></label>),
     "Wand", [], 1},
    {"a label's for over its wrapped control", ~s(<label for="target">Wand <input id="other"></label><input id="target">),
     "Wand", [], 1},
    {"aria-labelledby over a wrapping label",
     ~s(<span id="name">Patronus</span><label>Wrong <button aria-labelledby="name">Cast</button></label>), "Wrong", [],
     0},
    {"an empty aria-label falling back to a label",
     ~s(<label for="target">House</label><input id="target" aria-label="  ">), "House", [exact: true], 1},
    {"an aria-label over a label", ~s(<label for="target">House</label><input id="target" aria-label="Crest">), "House",
     [], 0},
    {"an aria-labelledby without a valid reference falling back to aria-label",
     ~s(<input aria-labelledby="missing" aria-label="Owl post">), "Owl post", [exact: true], 1},
    {"an aria-labelledby reference to the first element with an id",
     ~s(<span id="dup">Gryffindor</span><span id="dup">Slytherin</span><input aria-labelledby="dup">), "Slytherin", [],
     0},
    {"an aria-labelledby reference inside a template",
     ~s(<template><span id="spell">Lumos</span></template><input aria-labelledby="spell" aria-label="Nox">), "Nox",
     [exact: true], 1},
    {"a label for a hidden input", ~s(<label for="secret">Secret</label><input id="secret" type="hidden">), "Secret", [],
     0},
    {"a label for the first element with an id", ~s(<span id="dup"></span><label for="dup">Broom</label><input id="dup">),
     "Broom", [], 0},
    {"a label's whole text, including its control's", ~s(<label>Colour <select><option>Scarlet</option></select></label>),
     "Colour Scarlet", [exact: true], 1}
  ]

  for {case_name, html, label, options, expected} <- cases,
      driver <- [:static, :playwright] do
    @tag driver: driver
    test "finds a control from #{case_name} with #{driver}" do
      session =
        session_for_html(unquote(driver), unquote(html), base_url: Fluffy.TestServer.base_url())

      expect(session, unquote(label) |> by_label(unquote(options)) |> to_have_count(unquote(expected)))
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
      |> expect("ARIA Labelled Search" |> by_label(exact: true) |> to_have_count(1))
      |> expect("ARIA Search" |> by_label(exact: true) |> to_have_count(0))
      |> expect("HTML Search" |> by_label(exact: true) |> to_have_count(0))
    end

    @tag driver: driver
    test "matches each aria-labelledby reference rather than a combined label with #{driver}" do
      html = """
      <span id="first">Vault</span>
      <span id="second">address</span>
      <input aria-labelledby="first second">
      """

      session =
        session_for_html(unquote(driver), html, base_url: Fluffy.TestServer.base_url())

      session
      |> expect("Vault" |> by_label(exact: true) |> to_have_count(1))
      |> expect("address" |> by_label(exact: true) |> to_have_count(1))
      |> expect("Vault address" |> by_label(exact: true) |> to_have_count(0))
    end
  end
end
