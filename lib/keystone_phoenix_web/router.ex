defmodule KeystonePhoenixWeb.Router do
  use KeystonePhoenixWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", KeystonePhoenixWeb do
    pipe_through :api
  end
end
