defmodule Fluffy.Locator.RolesTest do
  use ExUnit.Case, async: true

  import Fluffy.Locator
  import Fluffy.Locator.Roles

  for role <- [:button, :link] do
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

      test "rejects what by_role rejects, and name: as an option" do
        assert_raise NimbleOptions.ValidationError, ~r/:exact.*boolean/, fn -> unquote(role)("Accio", exact: :yes) end

        assert_raise ArgumentError,
                     ~r/#{unquote(role)}\/2 takes the accessible name as its first argument, not as name:/,
                     fn ->
                       unquote(role)("Accio", name: "Accio")
                     end
      end

      test "points a parent locator to by_role" do
        message =
          ~r/#{unquote(role)}\/2 takes the accessible name first.*by_role\(parent, :#{unquote(role)}, name: \.\.\.\)/

        assert_raise ArgumentError, message, fn -> "#potions" |> by_css() |> unquote(role)() end
        assert_raise ArgumentError, message, fn -> "#potions" |> by_css() |> unquote(role)("Inspect") end
        assert_raise ArgumentError, message, fn -> "#gringotts" |> frame_locator() |> unquote(role)("Withdraw") end
        assert_raise ArgumentError, message, fn -> unquote(role)(123) end
      end
    end
  end
end
