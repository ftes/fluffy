defmodule Fluffy.Locator.Roles do
  @moduledoc """
  Shorthands for the two most common role locators, buttons and links.

      import Fluffy.Locator.Roles

      session
      |> click(button("Brew potion"))
      |> click(link("Back to the dungeons"))

  These are Fluffy conveniences with no Playwright counterpart, so `import Fluffy.Locator`
  leaves them out. `button("Brew potion")` is `by_role(:button, name: "Brew potion")`, the
  same `Fluffy.Locator`: a substring match unless `exact: true`, and every other role option.
  The name is the argument, so `name:` is not an option here. To match inside a parent, use
  `by_role(parent, :button, name: "Brew potion")`.

  `Phoenix.Component` exports `link/1` and a generated `CoreComponents` exports `button/1`.
  Where a module imports them, write `import Phoenix.Component, except: [link: 1]` and
  `import MyAppWeb.CoreComponents, except: [button: 1]`, or call
  `Fluffy.Locator.Roles.button/2` in full.
  """
  @moduledoc groups: ["Constructors"]

  alias Fluffy.Locator
  alias Fluffy.Options

  @typedoc "An accessible name, as `by_role`'s `name:` takes it."
  @type name :: String.t() | Regex.t() | Playwright.RegExp.t()

  @typedoc "A `Fluffy.Locator.by_role/2` option other than `name:`."
  @type option :: unquote(NimbleOptions.option_typespec(Options.role_shorthand_schema()))

  @doc group: "Constructors"
  @doc """
  Matches buttons by accessible name, as `Fluffy.Locator.by_role(:button, name: name)`.

      session |> click(button("Brew potion"))

      button(~r/^Inspect/)
  """
  @spec button(name(), [option()]) :: Locator.t()
  def button(name, options \\ []), do: Locator.by_role(:button, options(:button, name, options))

  @doc group: "Constructors"
  @doc """
  Matches links by accessible name, as `Fluffy.Locator.by_role(:link, name: name)`.

      session |> click(link("Enter the chamber"))

      link("Owlery", exact: true)
  """
  @spec link(name(), [option()]) :: Locator.t()
  def link(name, options \\ []), do: Locator.by_role(:link, options(:link, name, options))

  defp options(role, name, options)
       when is_binary(name) or is_struct(name, Regex) or is_struct(name, Playwright.RegExp) do
    if is_list(options) and Keyword.has_key?(options, :name) do
      raise ArgumentError, "#{role}/2 takes the accessible name as its first argument, not as name:"
    end

    [name: name] ++ Options.validate_role_shorthand!(options)
  end

  defp options(role, name, _options) do
    raise ArgumentError,
          "#{role}/2 takes the accessible name first, got: #{inspect(name)}. " <>
            "To match inside a parent locator, use by_role(parent, :#{role}, name: ...)"
  end
end
