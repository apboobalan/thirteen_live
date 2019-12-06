defmodule ThirteenLiveWeb.Router do
  use ThirteenLiveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug Phoenix.LiveView.Flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", ThirteenLiveWeb do
    pipe_through :browser

    get "/howto", PageController, :howto
    live "/", GameView
    live "/:game_name", GameView
  end

  # Other scopes may use custom stacks.
  # scope "/api", ThirteenLiveWeb do
  #   pipe_through :api
  # end
end
