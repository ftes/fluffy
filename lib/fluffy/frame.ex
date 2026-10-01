defmodule Fluffy.Frame do
  @moduledoc """
  A live browser frame returned by `Fluffy.Event.frame_navigated/1`.

  A page has one main frame and may contain child frames. Metadata resolves
  current state; the navigation event does not wait for page loading to finish.
  """
  alias Fluffy.Page
  alias Fluffy.SessionRuntime
  alias PlaywrightEx.Connection

  @enforce_keys [:page, :id]
  defstruct [:page, :id]
  @opaque t :: %__MODULE__{page: Page.t(), id: String.t()}

  @doc false
  def new(page, id), do: %__MODULE__{page: page, id: id}

  @doc "Returns the frame's current URL."
  @spec url(t()) :: String.t()
  def url(%__MODULE__{} = frame) do
    context = context!(frame)

    case PlaywrightEx.Frame.snapshot(frame.id, connection: context.connection) do
      {:ok, snapshot} -> snapshot.url
      {:error, reason} -> raise ArgumentError, "frame is closed: #{inspect(reason)}"
    end
  end

  @doc "Returns the owning page's live handle."
  @spec page(t()) :: Page.t()
  def page(%__MODULE__{} = frame) do
    context!(frame)
    frame.page
  end

  @doc "Returns the parent frame, or nil for the main frame."
  @spec parent_frame(t()) :: t() | nil
  def parent_frame(%__MODULE__{} = frame) do
    context = context!(frame)

    case Connection.initializer!(context.connection, frame.id)[:parent_frame] do
      nil -> nil
      %{guid: guid} -> new(frame.page, guid)
    end
  end

  defp context!(frame) do
    Page.record(frame.page)

    case SessionRuntime.context(frame.page.runtime) do
      {:ok, context} -> context
      {:error, reason} -> raise ArgumentError, reason
    end
  end
end
