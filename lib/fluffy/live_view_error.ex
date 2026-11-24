defmodule Fluffy.LiveViewError do
  @moduledoc """
  The `Fluffy.OperationError.cause` when a Phoenix operation finds its LiveView unusable.

  `reason` is the view's exit reason when it exited during the operation,
  `{:client_crashed, reason}` when LiveViewTest's client for the view crashed, such as on
  a render with a duplicate id, or one of `{:nested_live_view_not_found, id, parent_id}` and
  `{:target_outside_nested_live_view, selector, root_selector}` when the page names a
  nested LiveView that LiveViewTest does not have.
  """

  defexception [:reason, :message]

  @impl true
  def exception(options) do
    reason = Keyword.fetch!(options, :reason)
    %__MODULE__{reason: reason, message: reason_message(reason)}
  end

  defp reason_message({:nested_live_view_not_found, id, parent_id}),
    do: "LiveView #{inspect(parent_id)} has no nested LiveView #{inspect(id)}"

  defp reason_message({:target_outside_nested_live_view, selector, root_selector}),
    do: "the target #{inspect(selector)} is outside its nested LiveView #{inspect(root_selector)}"

  defp reason_message({:client_crashed, {exception, stacktrace}}) when is_exception(exception),
    do: "LiveViewTest's client crashed: " <> Exception.format_banner(:error, exception, stacktrace)

  defp reason_message({:client_crashed, reason}), do: "LiveViewTest's client crashed: #{inspect(reason)}"

  defp reason_message(reason), do: "the LiveView exited: #{inspect(reason)}"
end
