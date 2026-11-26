defmodule Fluffy.Locator.Roles do
  @moduledoc """
  Shorthands for button, link, and heading locators.

      import Fluffy.Locator.Roles

      navigation = Fluffy.Locator.by_role(:navigation)

      session
      |> click(button("Brew potion"))
      |> click(navigation |> link("Back to the dungeons"))

      heading("Potions", level: 2)

  These are Fluffy conveniences with no Playwright counterpart, so `import Fluffy.Locator`
  leaves them out. Each takes an accessible name and the same options as
  `Fluffy.Locator.by_role/3`. Pass a locator or frame scope first to match inside it.

  `Phoenix.Component` exports `link/1` and a generated `CoreComponents` exports `button/1`.
  Where a module imports them, write `import Phoenix.Component, except: [link: 1]` and
  `import MyAppWeb.CoreComponents, except: [button: 1]`, or call
  `Fluffy.Locator.Roles.button/2` in full.
  """
  @moduledoc groups: ["Constructors"]

  alias Fluffy.FrameLocator
  alias Fluffy.Locator
  alias Fluffy.Options

  @typedoc "An accessible name, as `by_role`'s `name:` takes it."
  @type name :: Locator.role_name()

  @typedoc "A `Fluffy.Locator.by_role/3` option other than `name:`."
  @type option :: unquote(NimbleOptions.option_typespec(Options.role_shorthand_schema()))

  defguardp is_name(name) when is_binary(name) or is_struct(name, Regex) or is_struct(name, Playwright.RegExp)

  @doc group: "Constructors"
  @doc """
  Matches buttons by accessible name, as `Fluffy.Locator.by_role(:button, name)`.

      session |> click(button("Brew potion"))

      button(~r/^Inspect/)
  """
  @spec button(name(), [option()]) :: Locator.t()
  @spec button(Locator.scope(), name()) :: Locator.t()
  def button(name_or_scope, options_or_name \\ []), do: role_locator(:button, name_or_scope, options_or_name)

  @doc group: "Constructors"
  @doc "Matches buttons by accessible name inside a locator or frame scope, with options."
  @spec button(Locator.scope(), name(), [option()]) :: Locator.t()
  def button(parent, name, options), do: Locator.by_role(parent, :button, name, options)

  @doc group: "Constructors"
  @doc """
  Matches links by accessible name, as `Fluffy.Locator.by_role(:link, name)`.

      session |> click(link("Enter the chamber"))

      link("Owlery", exact: true)
  """
  @spec link(name(), [option()]) :: Locator.t()
  @spec link(Locator.scope(), name()) :: Locator.t()
  def link(name_or_scope, options_or_name \\ []), do: role_locator(:link, name_or_scope, options_or_name)

  @doc group: "Constructors"
  @doc "Matches links by accessible name inside a locator or frame scope, with options."
  @spec link(Locator.scope(), name(), [option()]) :: Locator.t()
  def link(parent, name, options), do: Locator.by_role(parent, :link, name, options)

  @doc group: "Constructors"
  @doc """
  Matches headings by accessible name, as `Fluffy.Locator.by_role(:heading, name)`.

      heading("Potions", level: 2)
  """
  @spec heading(name(), [option()]) :: Locator.t()
  @spec heading(Locator.scope(), name()) :: Locator.t()
  def heading(name_or_scope, options_or_name \\ []), do: role_locator(:heading, name_or_scope, options_or_name)

  @doc group: "Constructors"
  @doc "Matches headings by accessible name inside a locator or frame scope, with options."
  @spec heading(Locator.scope(), name(), [option()]) :: Locator.t()
  def heading(parent, name, options), do: Locator.by_role(parent, :heading, name, options)

  defp role_locator(role, parent, name)
       when (is_struct(parent, Locator) or is_struct(parent, FrameLocator)) and is_name(name) do
    Locator.by_role(parent, role, name)
  end

  defp role_locator(role, name, options) when is_name(name), do: Locator.by_role(role, name, options)

  defp role_locator(role, _name_or_scope, _options_or_name) do
    raise ArgumentError, "#{role} requires an accessible name, optionally preceded by a locator or frame scope"
  end
end
