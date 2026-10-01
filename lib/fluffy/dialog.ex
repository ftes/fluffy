defmodule Fluffy.Dialog do
  @moduledoc """
  A browser dialog delivered to event listeners and waits.

  Register a listener before the triggering action, assert on its metadata, then
  accept or dismiss it. An unresolved dialog blocks browser actions. A wait only
  observes the dialog; it does not handle it. With no dialog registrations,
  Playwright dismisses dialogs automatically.
  """
  @enforce_keys [:type, :message, :default_value, :connection, :id, :timeout]
  defstruct [:type, :message, :default_value, :connection, :id, :timeout]

  @type t :: %__MODULE__{
          type: :alert | :confirm | :prompt | :beforeunload,
          message: String.t(),
          default_value: String.t(),
          connection: GenServer.server(),
          id: String.t(),
          timeout: non_neg_integer()
        }

  @doc "Accepts the dialog, optionally supplying prompt text."
  @spec accept(t(), String.t() | nil) :: :ok
  def accept(%__MODULE__{} = dialog, prompt_text \\ nil) do
    options = [connection: dialog.connection, timeout: dialog.timeout]
    options = if is_nil(prompt_text), do: options, else: Keyword.put(options, :prompt_text, prompt_text)
    result!(PlaywrightEx.Dialog.accept(dialog.id, options))
  end

  @doc "Dismisses the dialog."
  @spec dismiss(t()) :: :ok
  def dismiss(%__MODULE__{} = dialog) do
    result!(PlaywrightEx.Dialog.dismiss(dialog.id, connection: dialog.connection, timeout: dialog.timeout))
  end

  defp result!({:ok, _}), do: :ok
  defp result!({:error, reason}), do: raise("Could not handle dialog: #{inspect(reason)}")
end
