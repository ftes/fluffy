defmodule Fluffy.Download do
  @moduledoc """
  A download available as soon as downloading starts.

  `suggested_filename`, `url` and `page` are available to event predicates. Read
  or save the contents separately; those operations wait for completion and raise
  on download failure. On Playwright, they cancel the download and raise once the
  session's `timeout:` passes without completion, as for an interrupted download
  on Firefox, which never completes. Handles belong to their session; saved files
  outlive it. On Playwright, reach `failure`, `cancel` and the rest of the
  `PlaywrightEx.Download` with `Fluffy.unwrap/2`.

  `path/1` also waits for completion, and raises after the session's `timeout:`
  without canceling the download. A Phoenix download is complete when delivered
  and held in memory, so `path/1` raises `Fluffy.CapabilityError`.
  """

  alias Fluffy.Backend.Playwright.Bounded
  alias Fluffy.CapabilityError

  @never_completed "its response may never end, or the browser may have stopped it " <>
                     "(Firefox never completes an interrupted download)"

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
    context = Fluffy.Page.context!(download.page)
    read_source!(download, options[:max_bytes], context)
  end

  @doc "Waits for completion and saves to the destination using bounded memory."
  @spec save_as(t(), Path.t()) :: :ok
  def save_as(%__MODULE__{} = download, destination) do
    context = Fluffy.Page.context!(download.page)
    save_source!(download, destination, context)
  end

  @doc """
  Waits for completion and returns the path of the downloaded file.

  Playwright deletes the file when the session ends. Raises if the download failed.
  """
  @spec path(t()) :: Path.t()
  def path(%__MODULE__{} = download) do
    context = Fluffy.Page.context!(download.page)
    source_path!(download, context)
  end

  defp read_source!(%{body: bytes}, limit, _context) when is_binary(bytes) do
    check_size!(byte_size(bytes), limit)
    bytes
  end

  defp read_source!(download, limit, context) do
    path = Path.join(System.tmp_dir!(), "fluffy-download-#{System.unique_integer([:positive])}")

    try do
      save_source!(download, path, context)
      check_size!(File.stat!(path).size, limit)
      File.read!(path)
    after
      File.rm(path)
    end
  end

  defp save_source!(%{body: bytes}, destination, _context) when is_binary(bytes), do: File.write!(destination, bytes)

  # Playwright waits for completion without a timeout of its own. A save left
  # pending would still write the file once the download completes, so a timeout
  # cancels the download.
  defp save_source!(%{native: %PlaywrightEx.Download{} = native}, destination, %{timeout: timeout}) do
    Bounded.within!(
      timeout,
      :save_as,
      fn -> with :ok <- PlaywrightEx.Download.save_as(native, destination), do: {:ok, :ok} end,
      after_timeout: fn -> Bounded.within(timeout, fn -> PlaywrightEx.Download.cancel(native) end) end,
      message:
        "the download did not complete within the session's timeout of #{timeout}ms and was canceled; " <>
          @never_completed
    )
  end

  defp source_path!(%{body: bytes}, _context) when is_binary(bytes) do
    raise CapabilityError,
      capability: :download_path,
      driver: :phoenix,
      detail: "a Phoenix download is held in memory and has no file; use read/2 or save_as/2"
  end

  defp source_path!(%{native: native}, %{timeout: timeout}) do
    Bounded.within!(timeout, :path, fn -> PlaywrightEx.Download.path(native) end,
      message: "the download did not complete within the session's timeout of #{timeout}ms for path; " <> @never_completed
    )
  end

  defp check_size!(size, limit) when size > limit do
    raise ExUnit.AssertionError,
      message: "Downloaded #{size} bytes, exceeding the configured :max_bytes limit of #{limit}"
  end

  defp check_size!(_size, _limit), do: :ok
end
