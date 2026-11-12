defmodule Fluffy.Page do
  @moduledoc """
  An opaque, live handle to one page in a session.

  Metadata resolves the latest state. Handles survive navigation, but a closed
  page cannot be used again. Newly created pages have distinct identities.
  """
  @moduledoc groups: ["Metadata", "Assertions"]

  alias Fluffy.SessionRuntime

  @enforce_keys [:runtime, :id]
  defstruct [:runtime, :id]

  @opaque t :: %__MODULE__{runtime: pid(), id: reference()}
  @type title_expectation :: String.t() | Regex.t()
  @typedoc "A URL as Playwright takes it: a string, a regular expression or a predicate over the URL string."
  @type url_expectation :: String.t() | Regex.t() | (String.t() -> as_boolean(term()))

  @doc false
  @spec new(pid(), reference()) :: t()
  def new(runtime, id), do: %__MODULE__{runtime: runtime, id: id}

  @doc group: "Metadata"
  @doc "Returns the page's current URL."
  @spec url(t()) :: String.t() | nil
  def url(page), do: snapshot(page).url

  @doc group: "Metadata"
  @doc "Returns the opener's page handle, or nil if there is no opener or it has closed."
  @spec opener(t()) :: t() | nil
  def opener(page) do
    case record(page).opener do
      nil -> nil
      id -> %__MODULE__{runtime: page.runtime, id: id}
    end
  end

  @doc false
  @spec id(t()) :: reference()
  def id(%__MODULE__{id: id}), do: id

  @doc false
  @spec record(t()) :: map()
  def record(%__MODULE__{runtime: runtime, id: id}) do
    case SessionRuntime.page(runtime, id) do
      {:ok, record} -> record
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc false
  @spec ensure_session!(t()) :: :ok
  def ensure_session!(page) do
    context!(page)
    :ok
  end

  @doc false
  @spec context!(t()) :: map()
  def context!(%__MODULE__{runtime: runtime}) do
    case SessionRuntime.context(runtime) do
      {:ok, context} -> context
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc false
  @spec snapshot(t()) :: map()
  def snapshot(%__MODULE__{runtime: runtime} = page), do: Fluffy.Backend.page_snapshot(runtime, record(page))
end
