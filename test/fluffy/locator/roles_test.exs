defmodule Fluffy.Locator.RolesTest do
  use ExUnit.Case, async: true

  import Fluffy.Locator
  import Fluffy.Locator.Roles

  for role <- [:button, :link, :heading] do
    describe "#{role}" do
      test "with a name is by_role with name:" do
        assert unquote(role)("Accio") == by_role(unquote(role), name: "Accio")
        assert unquote(role)(~r/^Acc/) == by_role(unquote(role), name: ~r/^Acc/)

        reg_exp = Playwright.RegExp.new(~r/^acc/i)
        assert unquote(role)(reg_exp) == by_role(unquote(role), name: reg_exp)
      end

      test "passes the other role options through" do
        assert unquote(role)("Accio", exact: true) == by_role(unquote(role), name: "Accio", exact: true)

        assert unquote(role)("Accio", disabled: false, include_hidden: true) ==
                 by_role(unquote(role), name: "Accio", disabled: false, include_hidden: true)
      end

      test "composes like any locator" do
        assert "Inspect" |> unquote(role)() |> nth(1) == unquote(role) |> by_role(name: "Inspect") |> nth(1)
      end

      test "matches inside a locator or frame with optional role options" do
        for scope <- [by_role(:dialog), frame_locator("#gringotts")],
            name <- ["Accio", ~r/^Acc/, Playwright.RegExp.new(~r/^acc/i)] do
          assert unquote(role)(scope, name) == by_role(scope, unquote(role), name)
          assert unquote(role)(scope, name, exact: true) == by_role(scope, unquote(role), name, exact: true)
        end
      end

      test "rejects what by_role rejects, and name: as an option" do
        assert_raise NimbleOptions.ValidationError, ~r/:exact.*boolean/, fn -> unquote(role)("Accio", exact: :yes) end

        assert_raise ArgumentError, ~r/either positionally or as name:, not both/, fn ->
          unquote(role)("Accio", name: "Accio")
        end

        assert_raise ArgumentError, ~r/either positionally or as name:, not both/, fn ->
          :dialog |> by_role() |> unquote(role)("Accio", name: "Accio")
        end
      end

      test "requires a name even inside a scope" do
        message = ~r/#{unquote(role)} requires an accessible name/

        assert_raise ArgumentError, message, fn -> "#potions" |> by_css() |> unquote(role)() end
        assert_raise ArgumentError, message, fn -> "#gringotts" |> frame_locator() |> unquote(role)(exact: true) end
        assert_raise ArgumentError, message, fn -> unquote(role)(123) end
      end
    end
  end

  test "heading takes a level with and without a scope" do
    dialog = by_role(:dialog)
    assert heading("Potions", level: 2) == by_role(:heading, "Potions", level: 2)
    assert heading(dialog, "Potions", level: 2) == by_role(dialog, :heading, "Potions", level: 2)
  end
end
