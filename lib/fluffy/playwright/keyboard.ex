defmodule Fluffy.Playwright.Keyboard do
  @moduledoc """
  Page-wide keyboard input for Playwright sessions, after Playwright's `Keyboard`.

  Keys go to whatever has focus. To target an element, use `Fluffy.press/4` or
  `Fluffy.Playwright.press_sequentially/4`. A navigation the input causes is
  adopted, as after an action. Use it through `alias Fluffy.Playwright.Keyboard`;
  the names are too generic to import. Phoenix sessions raise
  `Fluffy.CapabilityError`.
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
    {timeout, native} = split_options(:keyboard_press, options)
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
    {timeout, native} = split_options(:keyboard_type, options)
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

  defp split_options(action, options), do: Keyword.split(Options.validate_action!(action, options), [:timeout])

  defp input(session, operation, options, fun) do
    Fluffy.Playwright.__ensure_playwright_backend__!(session, :keyboard)
    keyboard_fun = fn page -> fun.(PlaywrightEx.Page.keyboard(page)) end
    Fluffy.__dispatch_driver__(session, :page_action, [operation, keyboard_fun, options])
  end
end
