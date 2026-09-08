defmodule FluffyConsumerWeb.Router do
  use FluffyConsumerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FluffyConsumerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FluffyConsumerWeb do
    pipe_through :browser

    get "/", PageController, :home
    get "/complete", PageController, :complete
  end

  # Other scopes may use custom stacks.
  # scope "/api", FluffyConsumerWeb do
  #   pipe_through :api
  # end
end
