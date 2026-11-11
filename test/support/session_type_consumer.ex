defmodule Fluffy.SessionTypeConsumer do
  @moduledoc false

  # Compiled by mix quality so Dialyzer checks the public API from a consumer
  # module, where Session.t() must remain compatible throughout the pipeline.
  @spec playwright_session(keyword()) :: Fluffy.Session.t()
  def playwright_session(options), do: Fluffy.start_session(:playwright, options)

  @spec visit(keyword(), String.t()) :: Fluffy.Session.t()
  def visit(options, url), do: options |> playwright_session() |> Fluffy.visit(url)

  @spec screenshot(Fluffy.Session.t(), String.t()) :: Fluffy.Session.t()
  def screenshot(session, path), do: Fluffy.Playwright.screenshot(session, path)

  @spec evaluate(Fluffy.Session.t(), String.t()) :: term()
  def evaluate(session, expression), do: Fluffy.Playwright.evaluate(session, expression)
end
