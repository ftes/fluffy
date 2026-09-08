defmodule Fluffy.Driver.Live.ActionResolver do
  @moduledoc false

  alias Fluffy.Locator
  alias Fluffy.Session

  def attempt(%Session{} = session, %Locator{} = locator, action) when is_function(action, 1) do
    client_dom = session |> Session.page_state() |> Map.fetch!(:client_dom)
    apply_action(session, client_dom, action)
  rescue
    error in Fluffy.StrictnessError ->
      case error.candidates do
        [] -> {:retry, {:strictness, locator, []}}
        _ambiguous -> reraise(error, __STACKTRACE__)
      end
  end

  defp apply_action(session, client_dom, action) do
    {:ok, {session, action.(client_dom)}}
  rescue
    error in Fluffy.ActionabilityError ->
      if retryable?(error) do
        {:retry, {:exception, error}}
      else
        reraise(error, __STACKTRACE__)
      end
  end

  defp retryable?(%Fluffy.ActionabilityError{action: action, reason: :disabled})
       when action in [:click, :fill, :check, :uncheck, :select_option] do
    true
  end

  defp retryable?(%Fluffy.ActionabilityError{action: :click, reason: :hidden}), do: true
  defp retryable?(%Fluffy.ActionabilityError{action: :fill, reason: :readonly}), do: true

  defp retryable?(%Fluffy.ActionabilityError{action: :select_option, reason: :option_not_found}), do: true

  defp retryable?(%Fluffy.ActionabilityError{}), do: false
end
