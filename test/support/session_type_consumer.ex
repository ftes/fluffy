defmodule Fluffy.SessionTypeConsumer do
  @moduledoc false

  # Compiled by mix quality so Dialyzer checks the public API from a consumer
  # module, where Session.t() must remain compatible throughout the pipeline.
  @spec traced_session(keyword()) :: Fluffy.Session.t()
  def traced_session(options) do
    :playwright
    |> Fluffy.start_session(options)
    |> Fluffy.Playwright.trace(open: false)
  end

  @spec visit_with_trace(keyword(), String.t()) :: Fluffy.Session.t()
  def visit_with_trace(options, url) do
    options |> traced_session() |> Fluffy.visit(url)
  end

  @spec screenshot(Fluffy.Session.t(), String.t()) :: Fluffy.Session.t()
  def screenshot(session, path), do: Fluffy.Playwright.screenshot(session, path)

  @spec evaluate(Fluffy.Session.t(), String.t()) :: term()
  def evaluate(session, expression), do: Fluffy.Playwright.evaluate(session, expression)
end
