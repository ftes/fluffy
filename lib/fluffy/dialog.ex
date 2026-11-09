defmodule Fluffy.Dialog do
  @moduledoc """
  A browser dialog delivered to event listeners and waits.

  Register a listener before the triggering action, assert on its metadata, then
  accept or dismiss it. An unresolved dialog blocks browser actions. A wait only
  observes the dialog; it does not handle it. With no dialog registrations,
  Playwright dismisses dialogs automatically. Reach the `PlaywrightEx.Dialog`
  with `Fluffy.unwrap_and_return/2`.
  """
  @enforce_keys [:type, :message, :default_value, :page, :native]
  defstruct [:type, :message, :default_value, :page, :native]

  @type t :: %__MODULE__{
          type: :alert | :confirm | :prompt | :beforeunload,
          message: String.t(),
          default_value: String.t(),
          page: Fluffy.Page.t() | nil
        }

  @doc "Accepts the dialog, optionally supplying prompt text."
  @spec accept(t(), String.t() | nil) :: :ok
  def accept(%__MODULE__{native: native}, prompt_text \\ nil), do: PlaywrightEx.Dialog.accept!(native, prompt_text)

  @doc "Dismisses the dialog."
  @spec dismiss(t()) :: :ok
  def dismiss(%__MODULE__{native: native}), do: PlaywrightEx.Dialog.dismiss!(native)

  @doc "Returns the page that opened the dialog, or nil if unknown."
  @spec page(t()) :: Fluffy.Page.t() | nil
  def page(%__MODULE__{page: page}), do: page
end
