defmodule Fluffy.Download do
  @moduledoc """
  A download available as soon as downloading starts.

  `suggested_filename`, `url` and `page` are available to event predicates. Read
  or save the contents separately; those operations wait for completion and raise
  on download failure, on Playwright a `Fluffy.OperationError` with PlaywrightEx's
  exception as its `cause`. As in Playwright, they have no timeout: a download that
  never completes, such as an interrupted one on Firefox, waits until the test times
  out. Handles belong to their session; saved files outlive it. On Playwright, reach
  `failure`, `cancel` and the rest of the `PlaywrightEx.Download` with
  `Fluffy.unwrap_and_return/2`.

  `path/1` also waits for completion and raises the same way. A Phoenix download is
  complete when delivered and held in memory, so `path/1` raises `Fluffy.CapabilityError`.
  """

  alias Fluffy.CapabilityError
  alias Fluffy.Internal.OperationFailure

  # A Phoenix download carries its `body`, a Playwright download its `native` handle.
  @enforce_keys [:suggested_filename, :url, :page]
  defstruct [:suggested_filename, :url, :page, :body, :native]

  @type t :: %__MODULE__{suggested_filename: String.t(), url: String.t(), page: Fluffy.Page.t()}

  @doc "Returns the page that started the download."
  @spec page(t()) :: Fluffy.Page.t()
  def page(%__MODULE__{page: page}), do: page

  @doc "Waits for completion and reads the bytes, limited to 10 MB by default."
  @spec read(t(), keyword()) :: binary()
  def read(%__MODULE__{} = download, options \\ []) do
    options = NimbleOptions.validate!(options, max_bytes: [type: :non_neg_integer, default: 10_000_000])
    # Raises once the session is closed.
    Fluffy.Page.context!(download.page)
    read_source!(download, options[:max_bytes])
  end

  @doc "Waits for completion and saves to the destination using bounded memory."
  @spec save_as(t(), Path.t()) :: :ok
  def save_as(%__MODULE__{} = download, destination) do
    Fluffy.Page.context!(download.page)
    save_source!(download, destination, :save_as)
  end

  @doc """
  Waits for completion and returns the path of the downloaded file.

  Playwright deletes the file when the session ends. Raises if the download failed.
  """
  @spec path(t()) :: Path.t()
  def path(%__MODULE__{} = download) do
    Fluffy.Page.context!(download.page)
    source_path!(download)
  end

  defp read_source!(%{body: bytes}, limit) when is_binary(bytes) do
    check_size!(byte_size(bytes), limit)
    bytes
  end

  defp read_source!(download, limit) do
    path = Path.join(System.tmp_dir!(), "fluffy-download-#{System.unique_integer([:positive])}")

    try do
      save_source!(download, path, :read)
      check_size!(File.stat!(path).size, limit)
      File.read!(path)
    after
      File.rm(path)
    end
  end

  defp save_source!(%{body: bytes}, destination, _operation) when is_binary(bytes), do: File.write!(destination, bytes)

  # As for an action, PlaywrightEx's error becomes the cause of a `Fluffy.OperationError`.
  defp save_source!(%{native: %PlaywrightEx.Download{} = native}, destination, operation) do
    with {:error, error} <- PlaywrightEx.Download.save_as(native, destination),
         do: OperationFailure.raise_playwright!(operation, nil, error)
  end

  defp source_path!(%{body: bytes}) when is_binary(bytes) do
    raise CapabilityError,
      capability: :download_path,
      driver: :phoenix,
      detail: "a Phoenix download is held in memory and has no file; use read/2 or save_as/2"
  end

  defp source_path!(%{native: native}) do
    case PlaywrightEx.Download.path(native) do
      {:ok, path} -> path
      {:error, error} -> OperationFailure.raise_playwright!(:path, nil, error)
    end
  end

  defp check_size!(size, limit) when size > limit do
    raise ExUnit.AssertionError,
      message: "Downloaded #{size} bytes, exceeding the configured :max_bytes limit of #{limit}"
  end

  defp check_size!(_size, _limit), do: :ok
end
