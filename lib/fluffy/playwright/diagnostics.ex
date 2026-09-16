defmodule Fluffy.Playwright.Diagnostics do
  @moduledoc false

  def format(%{__exception__: true} = error), do: Exception.message(error)

  def format({error, details}) do
    format(error) <>
      "\nAssertion details: " <> inspect(details, pretty: true, limit: :infinity, printable_limit: :infinity)
  end

  def format(%{error: error} = wrapper), do: format(error) <> call_log(wrapper)

  def format(%{message: message} = error) do
    "#{Map.get(error, :name, "Error")}: #{message}" <> call_log(error)
  end

  def format(error), do: inspect(error, pretty: true, limit: :infinity, printable_limit: :infinity)

  defp call_log(%{log: [_ | _] = log}), do: "\nCall log:\n" <> Enum.join(log, "\n")
  defp call_log(_error), do: ""
end
