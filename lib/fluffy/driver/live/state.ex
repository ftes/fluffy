defmodule Fluffy.Driver.Live.State do
  @moduledoc false

  alias Fluffy.Driver.Live.Document
  alias Fluffy.Driver.Live.UploadState
  alias Fluffy.Driver.Phoenix.ClientDOM

  @enforce_keys [:client_dom, :document, :view, :monitor, :client_monitor]
  defstruct [:client_dom, :document, :view, :monitor, :client_monitor, live_uploads: %UploadState{}]

  @type t :: %__MODULE__{
          client_dom: ClientDOM.t(),
          document: Document.t(),
          view: %Phoenix.LiveViewTest.View{},
          monitor: reference(),
          client_monitor: reference(),
          live_uploads: UploadState.t()
        }

  # The monitors on the view and its LiveViewTest client tag their messages, so
  # a test's own `receive {:DOWN, ...}` can't take them.
  @down_tag :fluffy_live_view_down

  @spec monitor(pid()) :: reference()
  def monitor(pid), do: :erlang.monitor(:process, pid, tag: @down_tag)

  @spec down_tag() :: atom()
  def down_tag, do: @down_tag
end
