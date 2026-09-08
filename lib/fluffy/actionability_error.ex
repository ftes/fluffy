defmodule Fluffy.ActionabilityError do
  @moduledoc """
  Raised when an element exists but cannot receive the requested action.
  """

  defexception [:action, :reason, :locator, :target, :message]

  @impl true
  def exception(options) do
    action = Keyword.fetch!(options, :action)
    reason = Keyword.fetch!(options, :reason)
    locator = Keyword.get(options, :locator)
    target = Keyword.get(options, :target)

    description =
      cond do
        locator -> Fluffy.Locator.describe(locator)
        is_binary(target) -> target
        true -> raise ArgumentError, "ActionabilityError requires :locator or :target"
      end

    %__MODULE__{
      action: action,
      reason: reason,
      locator: locator,
      target: target,
      message: "Cannot #{action} #{description} because the target is #{reason_label(reason)}."
    }
  end

  defp reason_label(:not_editable), do: "not editable"
  defp reason_label(:not_checkable), do: "not checkable"
  defp reason_label(:not_selectable), do: "not selectable"
  defp reason_label(:cannot_uncheck_radio), do: "cannot uncheck a selected radio"
  defp reason_label(:disabled_option), do: "a disabled option"
  defp reason_label(:option_not_found), do: "the requested option was not found"
  defp reason_label(reason), do: to_string(reason)
end
