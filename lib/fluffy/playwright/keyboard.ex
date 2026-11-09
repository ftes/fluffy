defmodule Fluffy.Playwright.Keyboard do
  @moduledoc """
  Page-wide keyboard input for Playwright sessions, after Playwright's `Keyboard`.

  Keys go to whatever has focus. To target an element, use `Fluffy.press/4` or
  `Fluffy.Playwright.press_sequentially/4`. Use it through
  `alias Fluffy.Playwright.Keyboard`; the names are too generic to import. Phoenix
  sessions raise `Fluffy.CapabilityError`.

  Unlike `Fluffy.press/4`, these functions do not wait for a navigation the input
  starts, as in Playwright: they can return before it commits, and the next action
  can race it. If the input navigates, `expect` something on the new page before
  the next action; the session adopts the new document then.
  """

  alias Fluffy.Options
  alias Fluffy.Session
  alias PlaywrightEx.Keyboard, as: BrowserKeyboard

  @type press_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:keyboard_press)))
  @type type_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:keyboard_type)))

  @doc playwright_only: true
  @doc """
  Presses `key`, a Playwright key name, character, or combination such as `"Control+A"`.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:keyboard_press)}.

  #{NimbleOptions.docs(Options.action_schema(:keyboard_press))}
  """
  @spec press(Session.t(), String.t(), [press_option()]) :: Session.t()
  def press(%Session{} = session, key, options \\ []) when is_binary(key) do
    {timeout, native} = Options.split_action!(:keyboard_press, options)
    input(session, :"Keyboard.press", timeout, &BrowserKeyboard.press(&1, key, native))
  end

  @doc playwright_only: true
  @doc """
  Types `text` character by character, emitting key events for each.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:keyboard_type)}.

  #{NimbleOptions.docs(Options.action_schema(:keyboard_type))}
  """
  @spec type(Session.t(), String.t(), [type_option()]) :: Session.t()
  def type(%Session{} = session, text, options \\ []) when is_binary(text) do
    {timeout, native} = Options.split_action!(:keyboard_type, options)
    input(session, :"Keyboard.type", timeout, &BrowserKeyboard.type(&1, text, native))
  end

  @doc playwright_only: true
  @doc "Holds `key` down until `up/3`. Accepts `timeout:`. See `PlaywrightEx.Keyboard.down/2`."
  @spec down(Session.t(), String.t(), [Fluffy.action_option()]) :: Session.t()
  def down(%Session{} = session, key, options \\ []) when is_binary(key) do
    input(session, :"Keyboard.down", Options.validate_action!(options), &BrowserKeyboard.down(&1, key))
  end

  @doc playwright_only: true
  @doc "Releases `key`. Accepts `timeout:`. See `PlaywrightEx.Keyboard.up/2`."
  @spec up(Session.t(), String.t(), [Fluffy.action_option()]) :: Session.t()
  def up(%Session{} = session, key, options \\ []) when is_binary(key) do
    input(session, :"Keyboard.up", Options.validate_action!(options), &BrowserKeyboard.up(&1, key))
  end

  @doc playwright_only: true
  @doc """
  Inserts `text` without key events, as an input method does. Accepts `timeout:`.
  See `PlaywrightEx.Keyboard.insert_text/2`.
  """
  @spec insert_text(Session.t(), String.t(), [Fluffy.action_option()]) :: Session.t()
  def insert_text(%Session{} = session, text, options \\ []) when is_binary(text) do
    input(session, :"Keyboard.insert_text", Options.validate_action!(options), &BrowserKeyboard.insert_text(&1, text))
  end

  defp input(session, operation, options, fun),
    do: Fluffy.Playwright.__page_input__(session, &PlaywrightEx.Page.keyboard/1, operation, options, fun)
end
