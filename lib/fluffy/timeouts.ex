defmodule Fluffy.Timeouts do
  @moduledoc false

  # The defaults of an operation without `timeout:`, Playwright Test's on every driver, from
  # Fluffy's config (`Fluffy.Options.config!/1`): `action_timeout` and `navigation_timeout`
  # (none by default, so the test's timeout bounds them), which the Playwright backend sets on
  # each context, and `expect_timeout` (5 s by default). A configured `expect_timeout: 0`
  # checks once, as an operation's own `timeout: 0`.

  @doc "The action timeout: actions, locator reads, `wait_for_function` and event waits."
  @spec action() :: timeout()
  def action, do: Fluffy.Options.config!(:action_timeout)

  @doc "The navigation timeout: `visit`, `reload`, history and waits for a URL or load state."
  @spec navigation() :: timeout()
  def navigation, do: Fluffy.Options.config!(:navigation_timeout)

  @doc "The expect timeout of assertions."
  @spec expect() :: timeout()
  def expect, do: Fluffy.Options.config!(:expect_timeout)

  @doc "An operation's `timeout:`, else `default` (a function of this module)."
  @spec get(keyword(), (-> timeout())) :: timeout()
  def get(options, default) when is_list(options) and is_function(default, 0),
    do: Keyword.get_lazy(options, :timeout, default)

  # As in Playwright, these take the navigation timeout and the rest the action timeout.
  @navigations [:visit, :reload, :go_back, :go_forward, :wait_for_load_state]

  @doc "An operation's `timeout:`, else its default."
  @spec operation(atom(), keyword()) :: timeout()
  def operation(operation, options) when operation in @navigations, do: get(options, &navigation/0)
  def operation(_operation, options), do: get(options, &action/0)

  @doc """
  The PlaywrightEx timeout of an action, wait or navigation: it can't check once, so it rejects
  `0` (`Fluffy.Deadline.playwright_operation!/2`).
  """
  @spec playwright_operation!(atom(), keyword()) :: pos_integer() | :infinity
  def playwright_operation!(operation, options),
    do: Fluffy.Deadline.playwright_operation!(operation, operation(operation, options))

  @doc "The PlaywrightEx timeout of an expectation: its `0` checks once (`Fluffy.Deadline.playwright/1`)."
  @spec playwright_expect(keyword()) :: pos_integer() | :infinity
  def playwright_expect(options), do: Fluffy.Deadline.playwright(get(options, &expect/0))
end
