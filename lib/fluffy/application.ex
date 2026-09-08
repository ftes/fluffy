defmodule Fluffy.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Fluffy.Sandbox.config()
    validate_playwright_config()
    Supervisor.start_link(children(), strategy: :rest_for_one, name: Fluffy.Supervisor)
  end

  defp children do
    case playwright_config() do
      false ->
        []

      config ->
        if Keyword.get(config, :enabled, true) do
          timeout = Keyword.fetch!(config, :timeout)

          [
            Fluffy.Playwright.SubscriptionRegistry,
            {DynamicSupervisor, strategy: :one_for_one, name: Fluffy.BrowserRuntime.Supervisor},
            {Fluffy.BrowserRuntime,
             timeout: timeout,
             engine: Keyword.get(config, :engine, :chromium),
             playwright_options: [
               executable: Keyword.fetch!(config, :executable),
               js_logger: normalize_js_logger(Keyword.fetch!(config, :js_logger)),
               timeout: timeout
             ],
             launch_options: Keyword.fetch!(config, :launch_options)}
          ]
        else
          []
        end
    end
  end

  defp validate_playwright_config do
    playwright_config()
    :ok
  end

  defp playwright_config do
    :fluffy
    |> Application.get_env(:playwright, false)
    |> Fluffy.Options.validate_playwright!()
  end

  defp normalize_js_logger(false), do: nil
  defp normalize_js_logger(module), do: module
end
