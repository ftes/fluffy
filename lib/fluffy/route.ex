defmodule Fluffy.Route do
  @moduledoc """
  A browser request held by a handler of `Fluffy.Playwright.route/4`.

  `request` is the intercepted `PlaywrightEx.Request`. Answer the route once, with
  `fulfill/2`, `continue/2`, `abort/2` or `fallback/2`, from the handler or from
  any other process it passes the route to. As in Playwright, a request never
  answered hangs until the action waiting for it times out.

  Answers raise on failure. Reach the `PlaywrightEx.Route`, for members Fluffy does
  not wrap, with `Fluffy.unwrap_and_return/2`. See
  [Routing requests](advanced-events.md#routing-requests).
  """

  @enforce_keys [:request, :native]
  defstruct [:request, :native]

  @type t :: %__MODULE__{request: PlaywrightEx.Request.t()}

  @doc """
  Answers the request without reaching the server.

  Accepts the options of `PlaywrightEx.Route.fulfill/2`, such as `:status`,
  `:headers`, `:body`, `:json`, `:content_type` and `:path`.

      Fluffy.Route.fulfill(route, json: %{name: "Harry"})
      Fluffy.Route.fulfill(route, status: 503, body: "Down for maintenance")
  """
  @spec fulfill(t(), PlaywrightEx.Route.fulfill_options()) :: :ok
  def fulfill(%__MODULE__{} = route, options \\ []), do: PlaywrightEx.Route.fulfill!(route.native, options)

  @doc """
  Performs the request and returns its `PlaywrightEx.APIResponse`, without answering
  the route. Pass it to `fulfill/2` to answer, as is or with overrides:

      response = Fluffy.Route.fetch(route)
      Fluffy.Route.fulfill(route, response: response, status: 201)

  Accepts the options of `PlaywrightEx.Route.fetch/2`, such as `:url`, `:method`,
  `:headers`, `:post_data`, `:timeout`, and raises on failure. As for Playwright
  actions, `timeout: 0` raises `ArgumentError`, since Fluffy's 0 means check once;
  `timeout: :infinity` means no timeout. Read the response with the functions of
  `PlaywrightEx.APIResponse`.
  """
  @spec fetch(t(), PlaywrightEx.Route.fetch_options()) :: PlaywrightEx.APIResponse.t()
  def fetch(%__MODULE__{} = route, options \\ []) do
    {timeout, native} = Keyword.split(options, [:timeout])

    timeout =
      for {:timeout, timeout} <- Fluffy.Options.validate_action!(timeout),
          do: {:timeout, Fluffy.Deadline.playwright_operation!(:fetch, timeout)}

    PlaywrightEx.Route.fetch!(route.native, native ++ timeout)
  end

  @doc """
  Sends the request to the server, with no other route handling it.

  Accepts the overrides of `PlaywrightEx.Route.continue/2`: `:url`, `:method`,
  `:headers` and `:post_data`.
  """
  @spec continue(t(), PlaywrightEx.Route.continue_options()) :: :ok
  def continue(%__MODULE__{} = route, options \\ []), do: PlaywrightEx.Route.continue!(route.native, options)

  @doc """
  Hands the request to the next matching route, the one registered before this
  one, or sends it to the server if there is none.

  Accepts the same overrides as `continue/2`, which later handlers see.
  """
  @spec fallback(t(), PlaywrightEx.Route.fallback_options()) :: :ok
  def fallback(%__MODULE__{} = route, options \\ []), do: PlaywrightEx.Route.fallback!(route.native, options)

  @doc """
  Fails the request. `error_code` is one of the codes of
  `PlaywrightEx.Route.abort/2`, `"failed"` by default.
  """
  @spec abort(t(), String.t() | nil) :: :ok
  def abort(%__MODULE__{} = route, error_code \\ nil), do: PlaywrightEx.Route.abort!(route.native, error_code)
end
