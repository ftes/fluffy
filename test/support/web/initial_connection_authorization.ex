defmodule Fluffy.TestWeb.InitialConnectionAuthorization do
  @moduledoc false

  import Plug.Conn

  def init(options), do: options

  def call(%Plug.Conn{assigns: %{initial_principal: _principal}} = conn, _options), do: conn

  def call(conn, _options) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(403, "<main>Initial authorization required</main>")
    |> halt()
  end
end
