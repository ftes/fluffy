defmodule Fluffy.Timeouts do
  @moduledoc false

  # The defaults of an operation without `timeout:`. A browser session's are Playwright Test's:
  # the action and navigation timeouts as the test resolved them from every level
  # (`Playwright.Test.info().use`: config, project, module, tags) and the expect timeout of
  # `config :playwright, :expect`. Playwright's `0` means no limit, `:infinity` here. A Phoenix
  # session's, for action retries, assertions and event waits, is `config :fluffy,
  # phoenix_backend_timeout:` (1 s by default): an in-process session answers at once, so a long
  # wait is only for something that isn't there. Its `0` checks once, as a call's `timeout: 0`.

  alias Fluffy.Backend.Playwright.Context
  alias Fluffy.Session

  @doc """
  A browser session's action and navigation timeouts, from the test's options as the session
  starts (`Playwright.Test.info().use`), as Playwright.Test sets them on the test's contexts.
  """
  @spec browser(map()) :: %{action_timeout: timeout(), navigation_timeout: timeout()}
  def browser(use) do
    %{
      action_timeout: no_limit(Map.fetch!(use, :action_timeout)),
      navigation_timeout: no_limit(Map.fetch!(use, :navigation_timeout))
    }
  end

  @doc "A browser's action timeout: actions, locator reads, `wait_for_function` and event waits."
  @spec action(Session.t()) :: timeout()
  def action(session), do: Session.context(session).action_timeout

  @doc "The navigation timeout of a browser: `visit`, `reload`, history and waits for a URL or load state."
  @spec navigation(Session.t()) :: timeout()
  def navigation(session), do: Session.context(session).navigation_timeout

  @doc "An event wait's default: as Playwright's `waitForEvent`, a browser's action timeout."
  @spec event(Session.t()) :: timeout()
  def event(session) do
    case Session.context(session) do
      %Context{action_timeout: timeout} -> timeout
      _phoenix -> phoenix()
    end
  end

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
  @spec operation(Session.t(), atom(), keyword()) :: timeout()
  def operation(session, operation, options) when operation in @navigations,
    do: get(options, fn -> navigation(session) end)

  def operation(session, _operation, options), do: get(options, fn -> action(session) end)

  @doc """
  The Playwright timeout of an action, wait or navigation: it can't check once, so it rejects
  `0` (`Fluffy.Deadline.playwright_operation!/2`).
  """
  @spec playwright_operation!(Session.t(), atom(), keyword()) :: pos_integer() | :infinity
  def playwright_operation!(session, operation, options),
    do: Fluffy.Deadline.playwright_operation!(operation, operation(session, operation, options))

  @doc "The Playwright timeout of an expectation: its `0` checks once (`Fluffy.Deadline.playwright/1`)."
  @spec playwright_expect(keyword()) :: pos_integer() | :infinity
  def playwright_expect(options), do: Fluffy.Deadline.playwright(get(options, &expect/0))

  defp no_limit(0), do: :infinity
  defp no_limit(timeout), do: timeout
end
