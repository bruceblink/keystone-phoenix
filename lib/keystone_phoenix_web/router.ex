defmodule KeystonePhoenixWeb.Router do
  use KeystonePhoenixWeb, :router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KeystonePhoenixWeb do
    pipe_through :browser

    live "/", LoginLive, :index
  end

  scope "/", KeystonePhoenixWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/login/rsa-public-key", AuthController, :public_key
    post "/login", AuthController, :login
    post "/refresh-token", AuthController, :refresh
    post "/logout-refresh-token", AuthController, :logout_refresh_token
    get "/getLoginUserInfo", AuthController, :current_user
    get "/getRouters", AuthController, :routers
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
    post "/system/users", UserController, :create
    put "/system/users/:user_id", UserController, :update
    delete "/system/users/:user_ids", UserController, :delete
    put "/system/users/:user_id/password", UserController, :reset_password
    put "/system/users/:user_id/status", UserController, :change_status
    get "/system/depts", DepartmentController, :list
    get "/system/dept/:dept_id", DepartmentController, :show
    get "/system/depts/dropdown", DepartmentController, :dropdown
    post "/system/dept", DepartmentController, :create
    put "/system/dept/:dept_id", DepartmentController, :update
    delete "/system/dept/:dept_id", DepartmentController, :delete
    get "/system/post/list", PostController, :list
    get "/system/post/:post_id", PostController, :show
    post "/system/post", PostController, :create
    put "/system/post/:post_id", PostController, :update
    delete "/system/post", PostController, :delete
    get "/system/role/list", RoleController, :list
    get "/system/role/:role_id", RoleController, :show
    get "/system/menus", MenuController, :list
    get "/system/menus/dropdown", MenuController, :dropdown
    get "/system/menus/:menu_id", MenuController, :show
  end

  scope "/api", KeystonePhoenixWeb do
    pipe_through :api
  end
end
