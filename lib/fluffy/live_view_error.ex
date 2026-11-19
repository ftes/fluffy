defmodule Fluffy.LiveViewError do
  @moduledoc """
  The `Fluffy.OperationError.cause` when a Phoenix operation finds its LiveView unusable.

  `reason` is the view's exit reason when it exited during the operation, or one of
  `{:nested_live_view_not_found, id, parent_id}` and
  `{:target_outside_nested_live_view, selector, root_selector}` when the page names a
  nested LiveView that LiveViewTest does not have.
  """

  defexception [:reason, :message]

  @impl true
  def exception(options) do
    reason = Keyword.fetch!(options, :reason)
    %__MODULE__{reason: reason, message: message(reason)}
  end

  defp message({:nested_live_view_not_found, id, parent_id}),
    do: "LiveView #{inspect(parent_id)} has no nested LiveView #{inspect(id)}"

  defp message({:target_outside_nested_live_view, selector, root_selector}),
    do: "the target #{inspect(selector)} is outside its nested LiveView #{inspect(root_selector)}"

  defp message(reason), do: "the LiveView exited: #{inspect(reason)}"
end
