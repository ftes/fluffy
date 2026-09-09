defmodule Fluffy.Page do
  @moduledoc """
  One logical page or tab within a Fluffy session.

  A Phoenix page receives fresh Static or LiveView driver state whenever
  navigation commits a new document. Its monotonically increasing revision
  survives those state replacements.

  Construct page assertions with `Fluffy.Expect` or `Fluffy.Assert`.
  """
  @moduledoc groups: ["Metadata", "Assertions"]

  @enforce_keys [:id, :driver, :state]
  defstruct [:id, :driver, :state, :url, :status, :opener, revision: 0]

  @opaque t :: %__MODULE__{
            id: term(),
            driver: :unvisited | :static | :live | :playwright,
            state:
              Fluffy.Driver.Unvisited.State.t()
              | Fluffy.Driver.Static.State.t()
              | Fluffy.Driver.Live.State.t()
              | Fluffy.Driver.Playwright.State.t(),
            url: String.t() | nil,
            status: non_neg_integer() | nil,
            opener: term() | nil,
            revision: non_neg_integer()
          }

  @type title_expectation :: String.t() | Regex.t()
  @type query_value :: String.t() | [String.t()]
  @type url_component ::
          {:path, String.t()}
          | {:query, %{String.t() => query_value()}}
          | {:query_mode, :exact | :subset}
          | {:fragment, String.t() | nil}
  @type url_expectation :: String.t() | Regex.t() | [url_component()]

  @doc group: "Metadata"
  @doc "Returns the session-local name of a captured page."
  @spec name(t()) :: term()
  def name(%__MODULE__{id: id}), do: id

  @doc group: "Metadata"
  @doc "Returns the page's canonical URL, if it has committed a document."
  @spec url(t()) :: String.t() | nil
  def url(%__MODULE__{url: url}), do: url

  @doc group: "Metadata"
  @doc "Returns the page's normalized main-resource response status, when known."
  @spec status(t()) :: non_neg_integer() | nil
  def status(%__MODULE__{status: status}), do: status

  @doc group: "Metadata"
  @doc "Returns the session-local name of the page that opened this page."
  @spec opener(t()) :: term() | nil
  def opener(%__MODULE__{opener: opener}), do: opener

  @doc group: "Metadata"
  @doc "Returns the page's monotonically increasing document revision."
  @spec revision(t()) :: non_neg_integer()
  def revision(%__MODULE__{revision: revision}), do: revision

  @doc false
  def commit(%__MODULE__{} = page, driver, state, url, options \\ []) do
    options = Keyword.validate!(options, status: page.status)

    %{
      page
      | driver: driver,
        state: state,
        url: url,
        status: options[:status],
        revision: page.revision + 1
    }
  end
end
