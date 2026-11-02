defmodule KeystonePhoenixWeb.Router do
  use KeystonePhoenixWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KeystonePhoenixWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/login/rsa-public-key", AuthController, :public_key
    post "/login", AuthController, :login
    post "/refresh-token", AuthController, :refresh
    post "/logout-refresh-token", AuthController, :logout_refresh_token
    get "/system/dict/types", DictionaryController, :list_types
    get "/system/dict/type/list", DictionaryController, :list_types
    get "/system/dict/type/:dict_id", DictionaryController, :show_type
    get "/system/dict/data/list", DictionaryController, :list_data
    get "/system/dict/data/type/:dict_type", DictionaryController, :list_data_by_type
    get "/system/dict/data/:dict_code", DictionaryController, :show_data
    post "/system/dict/type", DictionaryController, :create_type
    put "/system/dict/type/:dict_id", DictionaryController, :update_type
    delete "/system/dict/type/:dict_id", DictionaryController, :delete_type
    post "/system/dict/data", DictionaryController, :create_data
    put "/system/dict/data/:dict_code", DictionaryController, :update_data
    delete "/system/dict/data/:dict_code", DictionaryController, :delete_data
    get "/system/configs", ConfigController, :list
    get "/system/config/:config_id", ConfigController, :show
    post "/system/config", ConfigController, :create
    put "/system/config/:config_id", ConfigController, :update
    delete "/system/configs/cache", ConfigController, :refresh_cache
    get "/system/users", UserController, :list
    get "/system/users/:user_id", UserController, :show
  end

  scope "/api", KeystonePhoenixWeb do
    pipe_through :api
  end
end
