defmodule Fluffy.Driver.Live.State do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.Driver.Live.Document
  alias Fluffy.Driver.Live.UploadState

  @enforce_keys [:client_dom, :document, :view, :monitor]
  defstruct [:client_dom, :document, :view, :monitor, live_uploads: %UploadState{}]

  @type t :: %__MODULE__{
          client_dom: ClientDOM.t(),
          document: Document.t(),
          view: %Phoenix.LiveViewTest.View{},
          monitor: reference(),
          live_uploads: UploadState.t()
        }

  # The view's monitor tags its message, so a test's own `receive {:DOWN, ...}`
  # can't take it.
  @down_tag :fluffy_live_view_down

  @spec monitor_view(pid()) :: reference()
  def monitor_view(pid), do: :erlang.monitor(:process, pid, tag: @down_tag)

  @spec down_tag() :: atom()
  def down_tag, do: @down_tag
end
