defmodule Fluffy.Navigation.Link do
  @moduledoc false
  @enforce_keys [:destination]
  defstruct [:destination, :download]

  @type t :: %__MODULE__{
          destination: String.t(),
          download: String.t() | nil
        }
end

defmodule Fluffy.Navigation.Submission do
  @moduledoc false
  @enforce_keys [:submission]
  defstruct [:submission]
  @type t :: %__MODULE__{submission: map()}
end

defmodule Fluffy.Navigation.Redirect do
  @moduledoc false
  @enforce_keys [:destination]
  defstruct [:destination, :flash]
  @type t :: %__MODULE__{destination: String.t(), flash: map() | String.t() | nil}
end

defmodule Fluffy.Navigation.Patch do
  @moduledoc false
  @enforce_keys [:destination, :state]
  defstruct [:destination, :state]
  @type t :: %__MODULE__{destination: String.t(), state: term()}
end

defmodule Fluffy.Navigation.BrowserCommitted do
  @moduledoc false
  @enforce_keys [:state, :url]
  defstruct [:live_navigation_cursor, :response, :state, :url]

  @type t :: %__MODULE__{
          live_navigation_cursor: non_neg_integer() | nil,
          response: map() | nil,
          state: term(),
          url: String.t()
        }
end

defmodule Fluffy.Navigation.BrowserPatch do
  @moduledoc false
  @enforce_keys [:state, :url]
  defstruct [:state, :url]
  @type t :: %__MODULE__{state: term(), url: String.t()}
end

defmodule Fluffy.Navigation.StaticConn do
  @moduledoc false
  @enforce_keys [:conn]
  defstruct [:conn]
  @type t :: %__MODULE__{conn: Plug.Conn.t()}
end

defmodule Fluffy.Navigation do
  @moduledoc false

  alias Fluffy.Navigation.BrowserCommitted
  alias Fluffy.Navigation.BrowserPatch
  alias Fluffy.Navigation.Link
  alias Fluffy.Navigation.Patch
  alias Fluffy.Navigation.Redirect
  alias Fluffy.Navigation.StaticConn
  alias Fluffy.Navigation.Submission

  @type t ::
          Link.t()
          | Submission.t()
          | Redirect.t()
          | Patch.t()
          | BrowserCommitted.t()
          | BrowserPatch.t()
          | StaticConn.t()

  def link(destination, options \\ []) do
    options = Keyword.validate!(options, [:download])
    %Link{destination: destination, download: options[:download]}
  end

  def submission(submission), do: %Submission{submission: submission}

  def redirect(destination, options \\ []) do
    options = Keyword.validate!(options, [:flash])
    %Redirect{destination: destination, flash: options[:flash]}
  end

  def patch(destination, state), do: %Patch{destination: destination, state: state}

  def browser_committed(url, state, options \\ []) do
    options = Keyword.validate!(options, [:live_navigation_cursor, :response])

    %BrowserCommitted{
      live_navigation_cursor: options[:live_navigation_cursor],
      response: options[:response],
      state: state,
      url: url
    }
  end

  def browser_patch(url, state), do: %BrowserPatch{state: state, url: url}
  def static_conn(%Plug.Conn{} = conn), do: %StaticConn{conn: conn}
end
