defmodule Fluffy.Timeouts do
  @moduledoc false

  # The defaults of an operation without `timeout:`, Playwright Test's on every driver:
  # `action_timeout` and `navigation_timeout` of `config :playwright_ex, :test` (none by default,
  # so the test's timeout bounds them), which PlaywrightEx.Test sets on each context, and the
  # `timeout` of `config :playwright_ex, :expect` (5 s by default), its matchers' default.
  # PlaywrightEx has no public reader of them, so they are read as it reads them. As there, a
  # configured `0` is no timeout; an operation's own `timeout: 0` checks once.

  @default_expect_timeout 5_000

  @doc "The action timeout: actions, locator reads, `wait_for_function` and event waits."
  @spec action() :: timeout()
  def action, do: test_timeout(:action_timeout)

  @doc "The navigation timeout: `visit`, `reload`, history and waits for a URL or load state."
  @spec navigation() :: timeout()
  def navigation, do: test_timeout(:navigation_timeout)

  @doc "The expect timeout of assertions."
  @spec expect() :: timeout()
  def expect do
    case :playwright_ex |> Application.get_env(:expect, []) |> config!(:expect) |> Keyword.get(:timeout) do
      nil -> @default_expect_timeout
      timeout -> timeout!(:expect, :timeout, timeout)
    end
  end

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

  defp test_timeout(key) do
    case :playwright_ex |> Application.get_env(:test, []) |> config!(:test) |> Keyword.get(key) do
      nil -> :infinity
      timeout -> timeout!(:test, key, timeout)
    end
  end

  defp config!(config, name) do
    if Keyword.keyword?(config),
      do: config,
      else:
        raise(ArgumentError, "config :playwright_ex, #{inspect(name)} must be a keyword list, got: #{inspect(config)}")
  end

  defp timeout!(_name, _key, timeout) when timeout in [0, :infinity], do: :infinity
  defp timeout!(_name, _key, timeout) when is_integer(timeout) and timeout > 0, do: timeout

  defp timeout!(name, key, timeout) do
    raise ArgumentError,
          "expected config :playwright_ex, #{inspect(name)}, #{key}: to be a nonnegative integer or :infinity, " <>
            "got: #{inspect(timeout)}"
  end
end
