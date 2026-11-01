defmodule KeystonePhoenixWeb.Router do
  use KeystonePhoenixWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KeystonePhoenixWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/system/dict/types", DictionaryController, :list_types
    get "/system/dict/type/list", DictionaryController, :list_types
    get "/system/dict/data/list", DictionaryController, :list_data
    get "/system/dict/data/type/:dict_type", DictionaryController, :list_data_by_type
  end

  scope "/api", KeystonePhoenixWeb do
    pipe_through :api
  end
end
