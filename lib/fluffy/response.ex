defmodule Fluffy.Response do
  @moduledoc """
  A browser response delivered by `Fluffy.Event.response/1` once its headers
  arrive.

  Fields follow Playwright's `Response` accessors; `request` is the
  `Fluffy.Request` that received it. Bodies are not retained: `body/1`,
  `text/1` and `json/1` read them from the browser, waiting for the response
  to end. They raise once the session is closed, after the session's `timeout:`,
  and when the browser does not have the body: a redirect has none, and whether
  one is still available after a later navigation depends on the browser.

      assert Fluffy.Response.json(response) == %{"saved" => true}

  Phoenix delivers no responses: `Fluffy.Event.response/1` raises
  `Fluffy.CapabilityError`. `security_details`, `server_addr` and other members
  stay on the `PlaywrightEx.Response` that `Fluffy.unwrap/2` passes.
  """

  alias Fluffy.Request

  @enforce_keys [:url, :status, :status_text, :headers, :request]
  defstruct [:url, :status, :status_text, :headers, :request, :native]

  @type t :: %__MODULE__{
          url: String.t(),
          status: non_neg_integer(),
          status_text: String.t(),
          headers: %{optional(String.t()) => String.t()},
          request: Request.t()
        }

  @doc "Returns whether the status is in the 200-299 range, or 0 as for a `file://` URL."
  @spec ok?(t()) :: boolean()
  def ok?(%__MODULE__{status: status}), do: status == 0 or status in 200..299

  @doc "Waits for the response to end and returns its body, as raw bytes."
  @spec body(t()) :: binary()
  def body(%__MODULE__{} = response), do: read!(response, :body, &PlaywrightEx.Response.body/1)

  @doc "Waits for the response to end and returns its body as text."
  @spec text(t()) :: String.t()
  def text(%__MODULE__{} = response), do: read!(response, :text, &PlaywrightEx.Response.text/1)

  @doc "Waits for the response to end and returns its body parsed as JSON. Raises if it is not valid JSON."
  @spec json(t()) :: term()
  def json(%__MODULE__{} = response), do: read!(response, :json, &PlaywrightEx.Response.json/1)

  @doc "Returns all response headers, with lowercase names, including the security-related ones `headers` leaves out."
  @spec all_headers(t()) :: %{optional(String.t()) => String.t()}
  def all_headers(%__MODULE__{} = response), do: read!(response, :all_headers, &PlaywrightEx.Response.all_headers/1)

  @doc """
  Returns the value of a header, matched case-insensitively, or nil if it is absent.

  Repeated headers join with `, `, or with a newline for `set-cookie`.
  """
  @spec header_value(t(), String.t()) :: String.t() | nil
  def header_value(%__MODULE__{} = response, name) when is_binary(name) do
    read!(response, :header_value, &PlaywrightEx.Response.header_value(&1, name))
  end

  @doc "Returns every value of a header, matched case-insensitively, such as each `set-cookie`."
  @spec header_values(t(), String.t()) :: [String.t()]
  def header_values(%__MODULE__{} = response, name) when is_binary(name) do
    read!(response, :header_values, &PlaywrightEx.Response.header_values(&1, name))
  end

  defp read!(%__MODULE__{request: request, native: native}, operation, fun) do
    Request.__bounded__!(request, operation, fn -> fun.(native) end)
  end
end
