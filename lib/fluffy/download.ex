defmodule Fluffy.Download do
  @moduledoc """
  A download available as soon as downloading starts.

  `suggested_filename` and `url` are available to event predicates. Read or save
  the contents separately; those operations wait for completion and raise on
  download failure. Handles belong to their session; saved files outlive it.
  """

  @enforce_keys [:suggested_filename, :url, :runtime, :source]
  defstruct [:suggested_filename, :url, :runtime, :source, :timeout]

  @type t :: %__MODULE__{
          suggested_filename: String.t(),
          url: String.t(),
          runtime: pid(),
          source: binary() | PlaywrightEx.Download.t(),
          timeout: non_neg_integer() | nil
        }

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

  defp read_source!(%{source: bytes}, limit) when is_binary(bytes) do
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

  defp save_source!(%{source: bytes}, destination) when is_binary(bytes), do: File.write!(destination, bytes)

  defp save_source!(%{source: %PlaywrightEx.Download{} = source, timeout: timeout}, destination) do
    case PlaywrightEx.Download.save_as(source, destination, timeout: timeout) do
      :ok -> :ok
      {:error, error} -> raise "Could not save download: #{inspect(error)}"
    end
  end

  defp check_size!(size, limit) when size > limit do
    raise ExUnit.AssertionError,
      message: "Downloaded #{size} bytes, exceeding the configured :max_bytes limit of #{limit}"
  end

  defp check_size!(_size, _limit), do: :ok

  defp ensure_session!(download) do
    case Fluffy.SessionRuntime.context(download.runtime) do
      {:ok, _} -> :ok
      {:error, reason} -> raise ArgumentError, reason
    end
  end
end
