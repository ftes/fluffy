defmodule Fluffy.Playwright.ConsoleLogger do
  @moduledoc """
  Default Logger adapter for browser console messages and uncaught page errors.

  Configure `js_logger: false` under `config :fluffy, :playwright` to disable
  browser logging, or provide another module implementing
  `PlaywrightEx.JsLogger`.
  """

  @behaviour PlaywrightEx.JsLogger

  require Logger

  @impl true
  def log(level, value, message) do
    metadata = [
      fluffy: :playwright,
      playwright_event: message[:method],
      playwright_page_id: get_in(message, [:params, :page, :guid])
    ]

    Logger.log(level, append_location(format_value(value), location(message)), metadata)
  end

  defp format_value(value) when is_binary(value), do: value
  defp format_value(%{error: %{message: message}}) when is_binary(message), do: message
  defp format_value(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  defp format_value(%{message: message}) when is_binary(message), do: message
  defp format_value(%{"message" => message}) when is_binary(message), do: message
  defp format_value(value), do: inspect(value)

  defp location(%{params: %{location: %{url: ""}}}), do: nil

  defp location(%{params: %{location: %{url: url} = location}}) when is_binary(url) do
    case {location[:line_number], location[:column_number]} do
      {line, column} when is_integer(line) and line > 0 and is_integer(column) and column > 0 ->
        "#{url}:#{line}:#{column}"

      {line, _column} when is_integer(line) and line > 0 ->
        "#{url}:#{line}"

      _other ->
        url
    end
  end

  defp location(_message), do: nil

  defp append_location(text, nil), do: text
  defp append_location(text, location), do: "#{text} (#{location})"
end
