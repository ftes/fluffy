defmodule Fluffy.Request do
  @moduledoc """
  A browser request delivered by `Fluffy.Event.request/1`,
  `Fluffy.Event.request_failed/1` and `Fluffy.Event.request_finished/1`, and as
  the request of a `Fluffy.Response` or a `Fluffy.Route`.

  Fields follow Playwright's `Request` accessors. `headers` has lowercase names.
  `post_data` is the buffered request body, as raw bytes (`postDataBuffer`), or
  nil. `page` is the live page handle when known, or nil (for example, a popup's
  initial request, or a request of a page that closed before Fluffy saw it).

  The functions below read from the browser, so they raise once the session is
  closed. As in Playwright, they have no timeout.
  Phoenix delivers no requests: `Fluffy.Event.request/1` raises
  `Fluffy.CapabilityError`. `timing`, `sizes` and other members stay on the
  `PlaywrightEx.Request` that `Fluffy.unwrap_and_return/2` passes.
  """

  alias Fluffy.Backend.Playwright.Events
  alias Fluffy.SessionRuntime

  @enforce_keys [:url, :method, :headers, :resource_type]
  defstruct [:url, :method, :headers, :resource_type, :post_data, :page, :native, :runtime]

  @type t :: %__MODULE__{
          url: String.t(),
          method: String.t(),
          headers: %{optional(String.t()) => String.t()},
          resource_type: String.t(),
          post_data: binary() | nil,
          page: Fluffy.Page.t() | nil
        }

  @doc "Returns all request headers, with lowercase names, including the security-related ones `headers` leaves out."
  @spec all_headers(t()) :: %{optional(String.t()) => String.t()}
  def all_headers(%__MODULE__{} = request) do
    __read__!(request, fn -> PlaywrightEx.Request.all_headers(request.native) end)
  end

  @doc "Returns the value of a header, matched case-insensitively, or nil if it is absent."
  @spec header_value(t(), String.t()) :: String.t() | nil
  def header_value(%__MODULE__{} = request, name) when is_binary(name) do
    __read__!(request, fn -> PlaywrightEx.Request.header_value(request.native, name) end)
  end

  @doc """
  Returns the request body parsed as JSON, or as a map for a form-encoded body, or nil without one.

  Raises if the body is not valid JSON.
  """
  @spec post_data_json(t()) :: term()
  def post_data_json(%__MODULE__{} = request) do
    context!(request)
    PlaywrightEx.Request.post_data_json(request.native)
  end

  @doc "Returns `%{errorText: reason}` for a request that failed, or nil for one that has not."
  @spec failure(t()) :: %{errorText: String.t()} | nil
  def failure(%__MODULE__{} = request) do
    context!(request)
    PlaywrightEx.Request.failure(request.native)
  end

  @doc "Returns the request whose redirect issued this one, or nil."
  @spec redirected_from(t()) :: t() | nil
  def redirected_from(%__MODULE__{} = request) do
    context!(request)
    redirect(request, PlaywrightEx.Request.redirected_from(request.native))
  end

  @doc "Returns the request this one redirected to, or nil."
  @spec redirected_to(t()) :: t() | nil
  def redirected_to(%__MODULE__{} = request) do
    context!(request)
    redirect(request, PlaywrightEx.Request.redirected_to(request.native))
  end

  defp redirect(_request, nil), do: nil
  defp redirect(%{runtime: runtime}, native), do: Events.request(%{runtime: runtime}, native)

  @doc false
  def __read__!(%__MODULE__{} = request, fun) do
    context!(request)

    case fun.() do
      {:ok, value} -> value
      {:error, error} -> raise error
    end
  end

  defp context!(%__MODULE__{runtime: runtime}), do: SessionRuntime.value!(SessionRuntime.context(runtime))
end
