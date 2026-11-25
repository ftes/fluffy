defmodule Fluffy.Conformance.RoleStateLocatorTest do
  use Fluffy.Support.Case, async: true

  import Fluffy
  import Fluffy.Expect
  import Fluffy.Locator

  alias Fluffy.Support.Web.RoleStatesLive

  for driver <- Drivers.all() do
    @tag driver: driver
    test "checked: reads the current checkedness and aria-checked with #{driver}" do
      unquote(driver)
      |> session()
      |> expect(to_have_count(by_role(:checkbox, checked: true), 2))
      |> expect(to_have_count(by_role(:checkbox, name: "Lumos", checked: true), 1))
      |> expect(to_have_count(by_role(:checkbox, name: "Invisibility Cloak", checked: true), 1))
      |> expect(to_have_count(by_role(:checkbox, name: "Nox", checked: false), 1))
      |> expect(to_have_count(by_role(:switch, name: "Time-Turner", checked: false), 1))
      |> expect(to_have_count(by_role(:radio, name: "Gryffindor", checked: true), 1))
      # Mixed is neither checked nor unchecked.
      |> expect(to_have_count(by_role(:menuitemcheckbox, checked: true), 0))
      |> expect(to_have_count(by_role(:menuitemcheckbox, checked: false), 0))
      |> check(by_role(:checkbox, name: "Nox", checked: false))
      |> uncheck(by_role(:checkbox, name: "Lumos", checked: true))
      |> check(by_role(:radio, name: "Slytherin"))
      |> expect(to_have_count(by_role(:checkbox, name: "Nox", checked: true), 1))
      |> expect(to_have_count(by_role(:checkbox, name: "Lumos", checked: false), 1))
      |> expect(to_have_count(by_role(:radio, name: "Slytherin", checked: true), 1))
      |> expect(to_have_count(by_role(:radio, name: "Gryffindor", checked: false), 1))
      |> expect(:group |> by_role() |> filter(has: by_role(:checkbox, name: "Nox", checked: true)) |> to_have_count(1))
    end

    @tag driver: driver
    test "selected: reads the current selection and aria-selected with #{driver}" do
      unquote(driver)
      |> session()
      |> expect(to_have_count(by_role(:option, name: "Elder", selected: true), 1))
      |> expect(to_have_count(by_role(:option, name: "Holly", selected: false), 1))
      |> expect(to_have_count(by_role(:option, name: "Hedwig", selected: true), 1))
      |> expect(to_have_count(by_role(:option, name: "Toad", selected: true), 1))
      |> expect(to_have_count(by_role(:option, name: "Cat", selected: false), 1))
      |> expect(to_have_count(by_role(:option, name: "Firebolt", selected: true), 1))
      |> expect(to_have_count(by_role(:option, name: "Nimbus", selected: false), 1))
      |> expect(to_have_count(by_role(:tab, selected: true), 1))
      |> expect(to_have_count(by_role(:tab, name: "Potions", selected: false), 1))
      # An option outside a select, in a hidden datalist, is selected by its attribute.
      |> expect(to_have_count(by_role(:option, name: "Mandrake root", selected: true, include_hidden: true), 1))
      |> expect(to_have_count(by_role(:option, name: "Bezoar", selected: false, include_hidden: true), 1))
      |> select_option(by_label("Wand", exact: true), "Vine")
      |> select_option(by_label("Pets"), ["Cat"])
      |> select_option(by_label("Owls"), "Errol")
      |> expect(to_have_count(by_role(:option, name: "Vine", selected: true), 1))
      |> expect(to_have_count(by_role(:option, name: "Elder", selected: false), 1))
      |> expect(to_have_count(by_role(:option, name: "Cat", selected: true), 1))
      |> expect(to_have_count(by_role(:option, name: "Toad", selected: false), 1))
      |> expect(to_have_count(by_role(:option, name: "Hedwig", selected: false), 1))
      |> expect(to_have_count(by_role(:option, name: "Errol", selected: true), 1))
    end

    @tag driver: driver
    test "disabled: follows the attribute, aria-disabled and fieldsets with #{driver}" do
      unquote(driver)
      |> session()
      |> expect(to_have_count(by_role(:button, name: "Restricted Section", disabled: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Forbidden Forest", disabled: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Chamber of Secrets", disabled: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Quidditch Pitch", disabled: true), 1))
      # Only a disabled fieldset's first legend stays enabled.
      |> expect(to_have_count(by_role(:button, name: "Prefects' Bathroom", disabled: false), 1))
      |> expect(to_have_count(by_role(:button, name: "Astronomy Tower", disabled: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Sorting Hat", disabled: false), 1))
      |> expect(to_have_count(by_role(:option, name: "Unicorn hair", disabled: true), 1))
      |> expect(to_have_count(by_role(:checkbox, name: "Lumos", disabled: false), 1))
    end

    @tag driver: driver
    test "expanded:, pressed: and level: read their attributes and headings with #{driver}" do
      unquote(driver)
      |> session()
      |> expect(to_have_count(by_role(:button, expanded: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Pensieve", expanded: false), 1))
      |> expect(to_have_count(by_role(:button, name: "Silencio", expanded: false), 0))
      |> expect(to_have_count(by_role(:button, pressed: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Silencio", pressed: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Sonorus", pressed: false), 1))
      |> expect(to_have_count(by_role(:button, name: "Riddikulus", pressed: true), 0))
      |> expect(to_have_count(by_role(:button, name: "Riddikulus", pressed: false), 0))
      |> expect(to_have_count(by_role(:heading, name: "Hogwarts", level: 1), 1))
      # A heading element's own level wins over aria-level.
      |> expect(to_have_count(by_role(:heading, level: 2), 1))
      |> expect(to_have_count(by_role(:heading, level: 5), 0))
      |> expect(to_have_count(by_role(:heading, name: "Fat Lady", level: 6), 1))
      |> expect(to_have_count(by_role(:heading, name: "Common room", level: 3), 1))
      |> expect(to_have_count(by_role(:heading, name: "Dormitory", level: 0), 1))
      |> expect(to_have_count(by_role(:listitem, level: 2), 1))
    end

    @tag driver: driver
    test "description: matches the accessible description like the name with #{driver}" do
      unquote(driver)
      |> session()
      |> expect(to_have_count(by_role(:button, description: "unlocks doors"), 1))
      |> expect(to_have_count(by_role(:button, description: "Unlocks doors", exact: true), 1))
      |> expect(to_have_count(by_role(:button, description: "unlocks", exact: true), 0))
      |> expect(to_have_count(by_role(:button, description: ~r/^Unlocks doors$/), 1))
      |> expect(to_have_count(by_role(:button, name: "Lumos Maxima", description: "wand tip"), 1))
      |> expect(to_have_count(by_role(:button, name: "Expelliarmus", description: "Disarms"), 1))
      # A hidden element still describes what references it.
      |> expect(to_have_count(by_role(:button, name: "Obliviate", description: "Erases memories"), 1))
    end

    @tag driver: driver
    test "include_hidden: also matches hidden elements and names them from hidden content with #{driver}" do
      unquote(driver)
      |> session()
      |> expect(to_have_count(by_role(:button, name: "Room of Requirement"), 0))
      |> expect(to_have_count(by_role(:button, name: "Room of Requirement", include_hidden: false), 0))
      |> expect(to_have_count(by_role(:button, name: "Room of Requirement", include_hidden: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Platform Nine and Three-Quarters"), 0))
      |> expect(to_have_count(by_role(:button, name: "Platform Nine and Three-Quarters", include_hidden: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Accio", exact: true), 1))
      |> expect(to_have_count(by_role(:button, name: "Accio Firebolt"), 0))
      |> expect(to_have_count(by_role(:button, name: "Accio Firebolt", include_hidden: true), 1))
    end

    @tag driver: driver
    test "a state option the role lacks raises when the locator resolves with #{driver}" do
      session = session(unquote(driver))
      exception = if unquote(driver) == :playwright, do: ExUnit.AssertionError, else: ArgumentError

      assert_raise exception, ~r/"pressed" attribute is only supported for roles: "button"/, fn ->
        expect(session, to_have_count(by_role(:link, pressed: true), 0))
      end

      assert_raise exception,
                   ~r/"level" attribute is only supported for roles: "heading", "listitem", "row", "treeitem"/,
                   fn -> expect(session, to_have_count(by_role(:button, name: "Pensieve", level: 1), 0)) end
    end
  end

  test "role options are validated when the locator is built" do
    assert_raise NimbleOptions.ValidationError, ~r/:pressed/, fn -> by_role(:button, pressed: "yes") end
    assert_raise NimbleOptions.ValidationError, ~r/:level/, fn -> by_role(:heading, level: "2") end
    assert_raise NimbleOptions.ValidationError, ~r/:has_text/, fn -> filter(by_css("li"), has_text: 1) end

    # Text options take a string, a Regex or a Playwright.RegExp; a Regex becomes a RegExp.
    for {key, locator} <- [description: &by_role(:button, description: &1), name: &by_role(:button, name: &1)] do
      assert_raise NimbleOptions.ValidationError, ~r/#{key}/, fn -> locator.(:x) end
      assert locator.(~r/x/i) == locator.(Playwright.RegExp.new("x", "i"))
    end

    assert inspect(by_role(:button, name: ~r/x/, pressed: true)) ==
             "#Fluffy.Locator<by_role(:button, name: #Playwright.RegExp</x/>, pressed: true)>"
  end

  defp session(:live), do: :phoenix |> start_session() |> visit("/live/role-states")
  defp session(driver), do: session_for_html(driver, RoleStatesLive.markup())
end
