defmodule FluffyConsumerWeb.PageController do
  use FluffyConsumerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def complete(conn, _params) do
    Plug.Conn.send_resp(conn, 200, "<!doctype html><h1>Consumer complete</h1>")
  end
end
