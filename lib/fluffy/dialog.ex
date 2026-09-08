defmodule Fluffy.Dialog do
  @moduledoc """
  A normalized browser dialog and the action Fluffy took to unblock it.

  Assertion constructors accept the capture key and return a `Fluffy.Expect`
  value for `Fluffy.expect/2`. Capture waits for the event; assertions inspect
  the retained result. Options follow `Fluffy.Expect`.
  """

  alias Fluffy.Expect

  @enforce_keys [:type, :message, :default_value]
  defstruct [:type, :message, :default_value, :action, :prompt_text]

  @type dialog_type :: :alert | :beforeunload | :confirm | :prompt | String.t()
  @type action :: :accept | :dismiss | nil

  @type t :: %__MODULE__{
          type: dialog_type(),
          message: String.t(),
          default_value: String.t(),
          action: action(),
          prompt_text: String.t() | nil
        }

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's type to equal the supplied value.
  """
  @spec to_have_type(term(), term(), [Expect.option()]) :: Expect.t()
  def to_have_type(key, expected, options \\ []) do
    Expect.new({:dialog, key}, :dialog_type, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's message to equal the supplied value.
  """
  @spec to_have_message(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_message(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:dialog, key}, :dialog_message, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's default value to equal the supplied value.
  """
  @spec to_have_default_value(term(), String.t(), [Expect.option()]) :: Expect.t()
  def to_have_default_value(key, expected, options \\ []) when is_binary(expected) do
    Expect.new({:dialog, key}, :dialog_default_value, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's action to equal the supplied value.
  """
  @spec to_have_action(term(), term(), [Expect.option()]) :: Expect.t()
  def to_have_action(key, expected, options \\ []) do
    Expect.new({:dialog, key}, :dialog_action, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the captured dialog's prompt text to equal the supplied value.
  """
  @spec to_have_prompt_text(term(), term(), [Expect.option()]) :: Expect.t()
  def to_have_prompt_text(key, expected, options \\ []) do
    Expect.new({:dialog, key}, :dialog_prompt_text, expected, options)
  end
end
