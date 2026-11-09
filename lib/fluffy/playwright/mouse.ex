defmodule Fluffy.Playwright.Mouse do
  @moduledoc """
  Page-wide mouse input for Playwright sessions, after Playwright's `Mouse`.

  Coordinates are CSS pixels from the top-left corner of the viewport. To target
  an element, use `Fluffy.click/3` or `Fluffy.Playwright.hover/3`. Use it through
  `alias Fluffy.Playwright.Mouse`; the names are too generic to import. Phoenix
  sessions raise `Fluffy.CapabilityError`.

  Unlike `Fluffy.click/3`, these functions do not wait for a navigation the input
  starts, as in Playwright: they can return before it commits, and the next action
  can race it. If the input navigates, `expect` something on the new page before
  the next action; the session adopts the new document then.
  """

  alias Fluffy.Options
  alias Fluffy.Session
  alias PlaywrightEx.Mouse, as: BrowserMouse

  @type click_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:mouse_click)))
  @type dblclick_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:mouse_dblclick)))
  @type down_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:mouse_down)))
  @type up_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:mouse_up)))
  @type move_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:mouse_move)))

  @doc playwright_only: true
  @doc """
  Moves the mouse to `x`, `y` and clicks.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:mouse_click)}.

  #{NimbleOptions.docs(Options.action_schema(:mouse_click))}
  """
  @spec click(Session.t(), number(), number(), [click_option()]) :: Session.t()
  def click(%Session{} = session, x, y, options \\ []) when is_number(x) and is_number(y) do
    {timeout, native} = Options.split_action!(:mouse_click, options)
    input(session, :"Mouse.click", timeout, &BrowserMouse.click(&1, x, y, native))
  end

  @doc playwright_only: true
  @doc """
  Moves the mouse to `x`, `y` and double-clicks.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:mouse_dblclick)}.

  #{NimbleOptions.docs(Options.action_schema(:mouse_dblclick))}
  """
  @spec dblclick(Session.t(), number(), number(), [dblclick_option()]) :: Session.t()
  def dblclick(%Session{} = session, x, y, options \\ []) when is_number(x) and is_number(y) do
    {timeout, native} = Options.split_action!(:mouse_dblclick, options)
    input(session, :"Mouse.dblclick", timeout, &BrowserMouse.dblclick(&1, x, y, native))
  end

  @doc playwright_only: true
  @doc """
  Presses a mouse button at the current position.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:mouse_down)}.

  #{NimbleOptions.docs(Options.action_schema(:mouse_down))}
  """
  @spec down(Session.t(), [down_option()]) :: Session.t()
  def down(%Session{} = session, options \\ []) do
    {timeout, native} = Options.split_action!(:mouse_down, options)
    input(session, :"Mouse.down", timeout, &BrowserMouse.down(&1, native))
  end

  @doc playwright_only: true
  @doc """
  Releases a mouse button at the current position.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:mouse_up)}.

  #{NimbleOptions.docs(Options.action_schema(:mouse_up))}
  """
  @spec up(Session.t(), [up_option()]) :: Session.t()
  def up(%Session{} = session, options \\ []) do
    {timeout, native} = Options.split_action!(:mouse_up, options)
    input(session, :"Mouse.up", timeout, &BrowserMouse.up(&1, native))
  end

  @doc playwright_only: true
  @doc """
  Moves the mouse to `x`, `y`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:mouse_move)}.

  #{NimbleOptions.docs(Options.action_schema(:mouse_move))}
  """
  @spec move(Session.t(), number(), number(), [move_option()]) :: Session.t()
  def move(%Session{} = session, x, y, options \\ []) when is_number(x) and is_number(y) do
    {timeout, native} = Options.split_action!(:mouse_move, options)
    input(session, :"Mouse.move", timeout, &BrowserMouse.move(&1, x, y, native))
  end

  @doc playwright_only: true
  @doc "Scrolls by `delta_x`, `delta_y` with the wheel. Accepts `timeout:`. See `PlaywrightEx.Mouse.wheel/3`."
  @spec wheel(Session.t(), number(), number(), [Fluffy.action_option()]) :: Session.t()
  def wheel(%Session{} = session, delta_x, delta_y, options \\ []) when is_number(delta_x) and is_number(delta_y) do
    input(session, :"Mouse.wheel", Options.validate_action!(options), &BrowserMouse.wheel(&1, delta_x, delta_y))
  end

  defp input(session, operation, options, fun),
    do: Fluffy.Playwright.__page_input__(session, &PlaywrightEx.Page.mouse/1, operation, options, fun)
end
