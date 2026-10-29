defmodule Fluffy.Driver.Live.State do
  @moduledoc false

  alias Fluffy.ClientDOM
  alias Fluffy.Driver.Live.Document
  alias Fluffy.Driver.Live.UploadState

  @enforce_keys [:client_dom, :document, :view, :watcher]
  defstruct [:client_dom, :document, :view, :watcher, live_uploads: %UploadState{}]

  @type t :: %__MODULE__{
          client_dom: ClientDOM.t(),
          document: Document.t(),
          view: %Phoenix.LiveViewTest.View{},
          watcher: pid(),
          live_uploads: UploadState.t()
        }
end
