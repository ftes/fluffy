defmodule Fluffy.Download do
  @moduledoc """
  A download available as soon as downloading starts.

  `suggested_filename`, `url` and `page` are available to event predicates. Read
  or save the contents separately; those operations wait for completion and raise
  on download failure. On Playwright, they cancel the download and raise once the
  session's `timeout:` passes without completion, as for an interrupted download
  on Firefox, which never completes. Handles belong to their session; saved files outlive it. On Playwright, reach the `PlaywrightEx.Download` with
  `Fluffy.unwrap/2`.
  """

  alias Fluffy.Backend.Playwright.Bounded

  # A Phoenix download carries its `body`, a Playwright download its `native` handle.
  @enforce_keys [:suggested_filename, :url, :page]
  defstruct [:suggested_filename, :url, :page, :body, :native]

  @type t :: %__MODULE__{suggested_filename: String.t(), url: String.t(), page: Fluffy.Page.t()}

  @doc "Returns the page that started the download."
  @spec page(t()) :: Fluffy.Page.t()
  def page(%__MODULE__{page: page}), do: page

  @doc "Waits for completion and reads the bytes, limited to 10 MB by default."
  @spec read!(t(), keyword()) :: binary()
  def read!(%__MODULE__{} = download, options \\ []) do
    options = NimbleOptions.validate!(options, max_bytes: [type: :non_neg_integer, default: 10_000_000])
    context = Fluffy.Page.context!(download.page)
    read_source!(download, options[:max_bytes], context)
  end

  @doc "Waits for completion and saves to the destination using bounded memory."
  @spec save_as!(t(), Path.t()) :: :ok
  def save_as!(%__MODULE__{} = download, destination) do
    context = Fluffy.Page.context!(download.page)
    save_source!(download, destination, context)
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
          "its response may never end, or the browser may have stopped it (Firefox never " <>
          "completes an interrupted download)"
    )
  end

  defp check_size!(size, limit) when size > limit do
    raise ExUnit.AssertionError,
      message: "Downloaded #{size} bytes, exceeding the configured :max_bytes limit of #{limit}"
  end

  defp check_size!(_size, _limit), do: :ok
end
