defmodule Fluffy.Page do
  @moduledoc """
  One logical page or tab within a Fluffy session.

  A Phoenix page receives fresh Static or LiveView driver state whenever
  navigation commits a new document. Its monotonically increasing revision
  survives those state replacements.

  This module also constructs expectations whose target is a page, mirroring
  Playwright's page-specific assertion surface.
  """
  @moduledoc groups: ["Metadata", "Assertions"]

  alias Fluffy.Expect
  alias Fluffy.URLMatcher

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

  @doc group: "Assertions"
  @doc """
  Expects the active page title to equal a string or match a regular expression.

  Like Playwright's `toHaveTitle`, the assertion retries on Live and Playwright
  pages and normalizes whitespace before matching.

  ## Options

  #{NimbleOptions.docs(Fluffy.Options.expectation_schema())}
  """
  @spec to_have_title(title_expectation()) :: Expect.t()
  @spec to_have_title(title_expectation(), [Expect.option()]) :: Expect.t()
  def to_have_title(expected, options \\ [])
      when (is_binary(expected) or is_struct(expected, Regex)) and is_list(options) do
    Expect.new(:page, :title, expected, options)
  end

  @doc group: "Assertions"
  @doc """
  Expects the active page to have the requested URL.

  A string matches the complete canonical absolute URL after resolving a
  relative value against the session base URL. A regular expression matches
  that complete serialized URL.

  A keyword list selects structured components. `:path` and `:fragment` are
  exact serialized component values; omit either to ignore it. `:fragment`
  excludes the leading `#`, and `fragment: nil` requires no fragment.

  `:query` is a map from decoded parameter names to one value or an ordered
  list of repeated values. Ordering between distinct names is ignored while
  repeated-value order is retained. Bare names and names with an empty value
  both decode to `""`; `+` and `%20` both decode to a space. Exact mode is the
  default. `query_mode: :subset` permits unrelated names but still requires
  the complete ordered value list for each requested name.

  ## Structured components

  #{NimbleOptions.docs(Fluffy.Options.url_matcher_schema())}

  ## Assertion options

  #{NimbleOptions.docs(Fluffy.Options.expectation_schema())}
  """
  @spec to_have_url(url_expectation()) :: Expect.t()
  @spec to_have_url(url_expectation(), [Expect.option()]) :: Expect.t()
  def to_have_url(expected, options \\ [])

  def to_have_url(expected, options) when (is_binary(expected) or is_struct(expected, Regex)) and is_list(options) do
    Expect.new(:page, :url, expected, options)
  end

  def to_have_url(components, options) when is_list(components) and is_list(options) do
    Expect.new(:page, :url, URLMatcher.new!(components), options)
  end

  @doc group: "Assertions"
  @doc "Expects the active page's normalized main-resource status."
  @spec to_have_status(non_neg_integer(), [Expect.option()]) :: Expect.t()
  def to_have_status(expected, options \\ []) when is_integer(expected) and expected >= 0 do
    Expect.new(:page, :status, expected, options)
  end

  @doc group: "Assertions"
  @doc "Expects the active page to name the requested opener page."
  @spec to_have_opener(term(), [Expect.option()]) :: Expect.t()
  def to_have_opener(expected, options \\ []) when is_list(options) do
    Expect.new(:page, :opener, expected, options)
  end

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
