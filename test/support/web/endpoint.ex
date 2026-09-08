defmodule Fluffy.TestWeb.Endpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :fluffy

  @session_options [
    store: :cookie,
    key: "_fluffy_test",
    signing_salt: "fluffy-session",
    same_site: "Lax"
  ]

  plug(Phoenix.Ecto.SQL.Sandbox,
    header: Fluffy.Sandbox.header(),
    sandbox: Fluffy.Sandbox.allowance()
  )

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [Fluffy.Sandbox.connect_info(), session: @session_options]],
    longpoll: false
  )

  plug(Plug.Static,
    at: "/",
    from: {:fluffy, "priv/static"},
    gzip: false,
    only: ~w(assets)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(Fluffy.TestHTTPFixturePlug)

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(Fluffy.TestWeb.Router)
end
