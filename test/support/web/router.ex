defmodule Fluffy.TestWeb.Router do
  @moduledoc false

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Fluffy.TestWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :initial_connection_authorization do
    plug(Fluffy.TestWeb.InitialConnectionAuthorization)
  end

  scope "/", Fluffy.TestWeb do
    get("/health", PageController, :health)
    get("/harness", PageController, :harness)
    get("/stage", PageController, :harness)
    get("/chamber", PageController, :static)
    get("/actions/click", PageController, :click_source)
    get("/actions/live", PageController, :live_source)
    get("/actions/client-navigation", PageController, :client_navigation)
    get("/actions/history-source", PageController, :history_source)
    get("/actions/history-target", PageController, :history_target)
    get("/actions/history-push-state", PageController, :history_push_state)
    get("/actions/disconnected-live-root", PageController, :disconnected_live_root)
    get("/redirect/live-ready", PageController, :redirect_live_ready)
  end

  scope "/live", Fluffy.TestWeb do
    pipe_through(:browser)

    live_session :fluffy_sandbox, on_mount: Fluffy.Sandbox do
      live("/three-heads", CounterLive)
      live("/fluffy", SmokeLive)
      live("/async", AsyncLive)
      live("/chamber-map", NavigationLive)
      live("/secret-chamber", DestinationLive)
      live("/session", SessionLive)
      live("/database", DatabaseLive)
      live("/potions", FormLive)
      live("/file-navigation", FileNavigationLive)
      live("/scrolls", LiveUploadLive)
      live("/scrolls/:mode", LiveUploadLive)
      live("/mystic-creatures", ActionabilityLive)
      live("/action-retries", ActionRetryLive)
      live("/timing", TimingLive)
      live("/redirect-ready", RedirectReadyLive)
      live("/phoenix-html-link", PhoenixHTMLLinkLive)
      live("/nested", NestedParentLive)
      live("/enchanted-title", PageTitleLive)
      live("/keyboard", KeyboardLive)
    end
  end

  scope "/session", Fluffy.TestWeb do
    pipe_through(:browser)

    get("/start", PageController, :session_start)
    get("/show", PageController, :session_show)
  end

  scope "/initial-connection", Fluffy.TestWeb do
    pipe_through([:browser, :initial_connection_authorization])

    get("/chamber", PageController, :initial_connection_static)
  end

  scope "/initial-connection", Fluffy.TestWeb do
    pipe_through(:browser)

    get("/redirect", PageController, :initial_connection_redirect)
    get("/redirected", PageController, :initial_connection_redirected)
  end

  scope "/live", Fluffy.TestWeb do
    pipe_through([:browser, :initial_connection_authorization])

    live_session :fluffy_initial_connection, on_mount: Fluffy.Sandbox do
      live("/initial-connection", InitialConnectionLive)
    end
  end

  scope "/", Fluffy.TestWeb do
    pipe_through(:browser)

    get("/database", PageController, :database)
    get("/databases", PageController, :databases)
  end
end
