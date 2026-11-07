defmodule Fluffy.Download do
  @moduledoc """
  A download available as soon as downloading starts.

  `suggested_filename`, `url` and `page` are available to event predicates. Read
  or save the contents separately; those operations wait for completion and raise
  on download failure. Like Playwright, they have no timeout; on Firefox, an
  interrupted download never completes. Handles belong to their session; saved
  files outlive it. On Playwright, reach the `PlaywrightEx.Download` with
  `Fluffy.unwrap/2`.
  """

  # A Phoenix download carries its `body`, a Playwright download its `native` handle.
  @enforce_keys [:suggested_filename, :url, :page, :runtime]
  defstruct [:suggested_filename, :url, :page, :runtime, :body, :native]

  @type t :: %__MODULE__{suggested_filename: String.t(), url: String.t(), page: Fluffy.Page.t()}

  @doc "Returns the page that started the download."
  @spec page(t()) :: Fluffy.Page.t()
  def page(%__MODULE__{page: page}), do: page

  @doc "Waits for completion and reads the bytes, limited to 10 MB by default."
  @spec read!(t(), keyword()) :: binary()
  def read!(%__MODULE__{} = download, options \\ []) do
    options = NimbleOptions.validate!(options, max_bytes: [type: :non_neg_integer, default: 10_000_000])
    ensure_session!(download)
    read_source!(download, options[:max_bytes])
  end

  @doc "Waits for completion and saves to the destination using bounded memory."
  @spec save_as!(t(), Path.t()) :: :ok
  def save_as!(%__MODULE__{} = download, destination) do
    ensure_session!(download)
    save_source!(download, destination)
  end

  @doc false
  def ensure_session!(download) do
    case Fluffy.SessionRuntime.context(download.runtime) do
      {:ok, _} -> :ok
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  defp read_source!(%{body: bytes}, limit) when is_binary(bytes) do
    check_size!(byte_size(bytes), limit)
    bytes
  end

  defp read_source!(download, limit) do
    path = Path.join(System.tmp_dir!(), "fluffy-download-#{System.unique_integer([:positive])}")

    try do
      save_source!(download, path)
      check_size!(File.stat!(path).size, limit)
      File.read!(path)
    after
      File.rm(path)
    end
  end

  defp save_source!(%{body: bytes}, destination) when is_binary(bytes), do: File.write!(destination, bytes)

  defp save_source!(%{native: %PlaywrightEx.Download{} = native}, destination),
    do: PlaywrightEx.Download.save_as!(native, destination)

  defp check_size!(size, limit) when size > limit do
    raise ExUnit.AssertionError,
      message: "Downloaded #{size} bytes, exceeding the configured :max_bytes limit of #{limit}"
  end

  defp check_size!(_size, _limit), do: :ok
end
