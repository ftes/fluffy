defmodule Fluffy.Timeouts do
  @moduledoc false

  # The defaults of an operation without `timeout:`. A browser session's are Playwright Test's:
  # the action and navigation timeouts as the test resolved them from every level
  # (`Playwright.Test.info().use`: config, project, module, tags) and the expect timeout of
  # `config :playwright, :test, expect:`. Playwright's `0` means no limit, `:infinity` here. A Phoenix
  # session's, for action retries, assertions and event waits, is `config :fluffy,
  # phoenix_backend_timeout:` (1 s by default): an in-process session answers at once, so a long
  # wait is only for something that isn't there.

  alias Fluffy.Backend.Playwright.Context
  alias Fluffy.Session

  @typedoc "A Fluffy timeout (`Fluffy.Options.timeout/1`): `:once` checks once and `:infinity` is no limit."
  @type t :: pos_integer() | :once | :infinity

  @doc "A browser's action timeout: actions, locator reads, `wait_for_function` and event waits."
  @spec action(Session.t()) :: t()
  def action(session), do: Session.context(session).action_timeout

  @doc "The navigation timeout of a browser: `visit`, `reload`, history and waits for a URL or load state."
  @spec navigation(Session.t()) :: t()
  def navigation(session), do: Session.context(session).navigation_timeout

  @doc "An event wait's default: as Playwright's `waitForEvent`, a browser's action timeout."
  @spec event(Session.t()) :: t()
  def event(session) do
    case Session.context(session) do
      %Context{action_timeout: timeout} -> timeout
      _phoenix -> phoenix()
    end
  end

  @doc "A browser's expect timeout of assertions."
  @spec expect() :: t()
  def expect, do: Fluffy.Options.config!(:expect_timeout)

  @doc "A Phoenix session's timeout of action retries, assertions and event waits."
  @spec phoenix() :: t()
  def phoenix, do: Fluffy.Options.config!(:phoenix_backend_timeout)

  @doc "An operation's `timeout:`, else `default`."
  @spec get(keyword(), (-> t())) :: t()
  def get(options, default) when is_list(options) and is_function(default, 0),
    do: Keyword.get_lazy(options, :timeout, default)

  # As in Playwright, these take the navigation timeout and the rest the action timeout.
  @navigations [:visit, :reload, :go_back, :go_forward, :wait_for_load_state]

  @doc "A browser operation's `timeout:`, else its default."
  @spec operation(Session.t(), atom(), keyword()) :: t()
  def operation(session, operation, options) when operation in @navigations,
    do: get(options, fn -> navigation(session) end)

  def operation(session, _operation, options), do: get(options, fn -> action(session) end)

  @doc "The Playwright timeout of an expectation: its `:once` checks once (`Fluffy.Deadline.playwright/1`)."
  @spec playwright_expect(keyword()) :: pos_integer() | :infinity
  def playwright_expect(options), do: Fluffy.Deadline.playwright(get(options, &expect/0))

  @doc "A timeout of Playwright's config as Fluffy's: Playwright's `0` means no limit."
  @spec no_limit(non_neg_integer() | :infinity) :: t()
  def no_limit(0), do: :infinity
  def no_limit(timeout), do: timeout
end
