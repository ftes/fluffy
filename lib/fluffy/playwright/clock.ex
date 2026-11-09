defmodule Fluffy.Playwright.Clock do
  @moduledoc """
  Fake page clock and timers for Playwright sessions, after Playwright's `Clock`.

  Use it through `alias Fluffy.Playwright.Clock` and call `Clock.install/2`,
  `Clock.run_for/3` and so on; the names are too generic to import. Phoenix
  sessions raise `Fluffy.CapabilityError`. See
  [Controlling time](actions.md#controlling-time).
  """

  alias Fluffy.Options
  alias Fluffy.Session

  @type install_option :: unquote(NimbleOptions.option_typespec(Options.action_schema(:install_clock)))

  @typedoc "A time: epoch milliseconds, a `DateTime` or a string `Date` parses, such as `\"2024-02-02\"`."
  @type time :: integer() | String.t() | DateTime.t()

  @typedoc ~s(A duration: milliseconds or `"ss"`, `"mm:ss"` or `"hh:mm:ss"`.)
  @type ticks :: integer() | String.t()

  @doc playwright_only: true
  @doc """
  Installs fake timers with the clock at `time:`, the current time by default; time
  then flows normally.

  The clock replaces `Date`, `setTimeout`, `setInterval`, `requestAnimationFrame`,
  `performance` and the other timer functions of `PlaywrightEx.Clock.install/2` in
  every page of the session, including documents loaded later. Install it before
  visiting the page whose timers a test controls. The other clock functions
  install it if needed.

  ## Options

  Playwright-only options pass through to #{Options.native_reference(:install_clock)}.

  #{NimbleOptions.docs(Options.action_schema(:install_clock))}
  """
  @spec install(Session.t(), [install_option()]) :: Session.t()
  def install(%Session{} = session, options \\ []) do
    Fluffy.Playwright.__ensure_playwright_backend__!(session, :clock)
    {timeout, native} = Keyword.split(Options.validate_action!(:install_clock, options), [:timeout])
    clock(session, :"Clock.install", &PlaywrightEx.Clock.install(&1, native), timeout)
  end

  @doc playwright_only: true
  @doc """
  Jumps the clock to `time` and pauses it, firing due timers at most once.

  No timer fires until `run_for/3`, `fast_forward/3`, `pause_at/3` or
  `resume/2`. That includes the application's own timers, such as a LiveView
  `phx-debounce` or a `JS.transition/2`, which defers LiveView's DOM updates
  until it finishes. Fluffy's actions and waits do not rely on page timers.
  Install the clock at an earlier time and visit first, so the page loads with
  running timers. See `PlaywrightEx.Clock.pause_at/2`.

  Accepts `timeout:`, which defaults to the session's `timeout:`.
  """
  @spec pause_at(Session.t(), time(), [Fluffy.action_option()]) :: Session.t()
  def pause_at(%Session{} = session, time, options \\ []) do
    clock_call(session, :"Clock.pause_at", options, &PlaywrightEx.Clock.pause_at(&1, time))
  end

  @doc playwright_only: true
  @doc """
  Advances the clock by `ticks`, firing every timer due on the way.

  `ticks` is milliseconds or a string such as `"30"` (seconds), `"01:30"` or
  `"02:34:10"`. A navigation the timers start is adopted, as after an action.
  See `PlaywrightEx.Clock.run_for/2`.

  Accepts `timeout:`, which defaults to the session's `timeout:`.

      session
      |> Clock.install(time: ~U[2024-02-02 09:00:00Z])
      |> visit("/spells")
      |> Clock.pause_at(~U[2024-02-02 10:00:00Z])
      |> fill(by_label("Spell"), "Lumos")
      |> Clock.run_for(500)
      |> expect(to_be_visible(by_text("Lumos found")))
  """
  @spec run_for(Session.t(), ticks(), [Fluffy.action_option()]) :: Session.t()
  def run_for(%Session{} = session, ticks, options \\ []) do
    clock_call(session, :"Clock.run_for", options, &PlaywrightEx.Clock.run_for(&1, ticks))
  end

  @doc playwright_only: true
  @doc """
  Jumps the clock forward by `ticks`, firing due timers at most once, like a laptop
  waking from sleep.

  Takes `ticks` and `timeout:` like `run_for/3`. See
  `PlaywrightEx.Clock.fast_forward/2`.
  """
  @spec fast_forward(Session.t(), ticks(), [Fluffy.action_option()]) :: Session.t()
  def fast_forward(%Session{} = session, ticks, options \\ []) do
    clock_call(session, :"Clock.fast_forward", options, &PlaywrightEx.Clock.fast_forward(&1, ticks))
  end

  @doc playwright_only: true
  @doc """
  Resumes a paused clock; time flows and timers fire again.

  Accepts `timeout:`, which defaults to the session's `timeout:`. See
  `PlaywrightEx.Clock.resume/1`.
  """
  @spec resume(Session.t(), [Fluffy.action_option()]) :: Session.t()
  def resume(%Session{} = session, options \\ []) do
    clock_call(session, :"Clock.resume", options, &PlaywrightEx.Clock.resume/1)
  end

  @doc playwright_only: true
  @doc """
  Makes `Date` always return `time`, while timers keep running.

  Accepts `timeout:`, which defaults to the session's `timeout:`. See
  `PlaywrightEx.Clock.set_fixed_time/2`.
  """
  @spec set_fixed_time(Session.t(), time(), [Fluffy.action_option()]) :: Session.t()
  def set_fixed_time(%Session{} = session, time, options \\ []) do
    clock_call(session, :"Clock.set_fixed_time", options, &PlaywrightEx.Clock.set_fixed_time(&1, time))
  end

  @doc playwright_only: true
  @doc """
  Sets the clock's current time without firing timers, such as to test a time-zone
  or daylight saving shift.

  Accepts `timeout:`, which defaults to the session's `timeout:`. See
  `PlaywrightEx.Clock.set_system_time/2`.
  """
  @spec set_system_time(Session.t(), time(), [Fluffy.action_option()]) :: Session.t()
  def set_system_time(%Session{} = session, time, options \\ []) do
    clock_call(session, :"Clock.set_system_time", options, &PlaywrightEx.Clock.set_system_time(&1, time))
  end

  defp clock_call(session, operation, options, fun) do
    Fluffy.Playwright.__ensure_playwright_backend__!(session, :clock)
    clock(session, operation, fun, Options.validate_action!(options))
  end

  defp clock(session, operation, fun, options), do: Fluffy.__dispatch_driver__(session, :clock, [operation, fun, options])
end
