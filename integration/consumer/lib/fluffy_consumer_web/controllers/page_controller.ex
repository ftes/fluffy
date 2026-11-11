defmodule FluffyConsumerWeb.PageController do
  use FluffyConsumerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def hogwarts(conn, _params) do
    Plug.Conn.send_resp(conn, 200, "<!doctype html><h1>Welcome to Hogwarts</h1>")
  end

  def marauders_map(conn, _params) do
    send_download(conn, {:binary, "student,house\nHermione,Gryffindor\n"},
      filename: "marauders_map.csv"
    )
  end
end
