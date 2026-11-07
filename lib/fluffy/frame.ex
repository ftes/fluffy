defmodule Fluffy.Frame do
  @moduledoc """
  A live browser frame returned by `Fluffy.Event.frame_navigated/1`.

  A page has one main frame and may contain child frames. Metadata resolves
  current state; the navigation event does not wait for page loading to finish.
  """
  alias Fluffy.Page
  alias Fluffy.SessionRuntime

  @enforce_keys [:page, :native]
  defstruct [:page, :native]
  @opaque t :: %__MODULE__{page: Page.t(), native: PlaywrightEx.Frame.t()}

  @doc false
  def new(page, native), do: %__MODULE__{page: page, native: native}

  @doc "Returns the frame's current URL."
  @spec url(t()) :: String.t()
  def url(%__MODULE__{} = frame) do
    ensure_session!(frame)
    PlaywrightEx.Frame.url(frame.native)
  end

  @doc "Returns the owning page's live handle."
  @spec page(t()) :: Page.t()
  def page(%__MODULE__{} = frame) do
    ensure_session!(frame)
    frame.page
  end

  @doc "Returns the parent frame, or nil for the main frame."
  @spec parent_frame(t()) :: t() | nil
  def parent_frame(%__MODULE__{} = frame) do
    ensure_session!(frame)

    case PlaywrightEx.Frame.parent_frame(frame.native) do
      nil -> nil
      parent -> new(frame.page, parent)
    end
  end

  @doc false
  def native!(%__MODULE__{} = frame) do
    ensure_session!(frame)
    frame.native
  end

  defp ensure_session!(frame) do
    Page.record(frame.page)

    case SessionRuntime.context(frame.page.runtime) do
      {:ok, _context} -> :ok
      {:error, reason} -> raise ArgumentError, reason
    end
  end
end
