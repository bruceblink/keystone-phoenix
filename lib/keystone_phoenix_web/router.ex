defmodule KeystonePhoenixWeb.Router do
  use KeystonePhoenixWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KeystonePhoenixWeb do
    pipe_through :api

    get "/health", HealthController, :show
  end

  scope "/api", KeystonePhoenixWeb do
    pipe_through :api
  end
end
