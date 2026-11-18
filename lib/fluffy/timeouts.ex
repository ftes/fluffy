defmodule Fluffy.Timeouts do
  @moduledoc false

  # The defaults of an operation without `timeout:`. A browser session's are Playwright Test's:
  # the action and navigation timeouts as the test resolved them from every level
  # (`Playwright.Test.info().use`: config, project, module, tags) and the expect timeout of
  # `config :playwright, :expect`. Playwright's `0` means no limit, `:infinity` here. A Phoenix
  # session's, for action retries, assertions and event waits, is `config :fluffy,
  # phoenix_backend_timeout:` (1 s by default): an in-process session answers at once, so a long
  # wait is only for something that isn't there. Its `0` checks once, as a call's `timeout: 0`.

  @doc "A browser's action timeout: actions, locator reads, `wait_for_function` and event waits."
  @spec action() :: timeout()
  def action, do: test_use!(:action_timeout)

  @doc "The navigation timeout of a browser: `visit`, `reload`, history and waits for a URL or load state."
  @spec navigation() :: timeout()
  def navigation, do: test_use!(:navigation_timeout)

  @doc "A browser's expect timeout of assertions."
  @spec expect() :: timeout()
  def expect, do: Fluffy.Options.config!(:expect_timeout)

  @doc "A Phoenix session's timeout of action retries, assertions and event waits."
  @spec phoenix() :: timeout()
  def phoenix, do: Fluffy.Options.config!(:phoenix_backend_timeout)

  @doc "An operation's `timeout:`, else `default`."
  @spec get(keyword(), (-> timeout())) :: timeout()
  def get(options, default) when is_list(options) and is_function(default, 0),
    do: Keyword.get_lazy(options, :timeout, default)

  # As in Playwright, these take the navigation timeout and the rest the action timeout.
  @navigations [:visit, :reload, :go_back, :go_forward, :wait_for_load_state]

  @doc "A browser operation's `timeout:`, else its default."
  @spec operation(atom(), keyword()) :: timeout()
  def operation(operation, options) when operation in @navigations, do: get(options, &navigation/0)
  def operation(_operation, options), do: get(options, &action/0)

  @doc """
  The Playwright timeout of an action, wait or navigation: it can't check once, so it rejects
  `0` (`Fluffy.Deadline.playwright_operation!/2`).
  """
  @spec playwright_operation!(atom(), keyword()) :: pos_integer() | :infinity
  def playwright_operation!(operation, options),
    do: Fluffy.Deadline.playwright_operation!(operation, operation(operation, options))

  @doc "The Playwright timeout of an expectation: its `0` checks once (`Fluffy.Deadline.playwright/1`)."
  @spec playwright_expect(keyword()) :: pos_integer() | :infinity
  def playwright_expect(options), do: Fluffy.Deadline.playwright(get(options, &expect/0))

  # Every session belongs to a registered test (`Fluffy.TestInfo.fetch!/0`).
  defp test_use!(key), do: no_limit(Map.fetch!(Fluffy.TestInfo.fetch!().use, key))

  defp no_limit(0), do: :infinity
  defp no_limit(timeout), do: timeout
end
