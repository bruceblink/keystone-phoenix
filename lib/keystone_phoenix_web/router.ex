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

    # 业务接口支持 Bearer 和 API Key；敏感的人类会话入口由 RejectApiKey 拒绝。
    plug KeystonePhoenixWeb.Plugs.ApiKeyAuthenticate
    plug KeystonePhoenixWeb.Plugs.OperationLog
  end

  pipeline :event_stream do
    plug :accepts, ["sse"]
  end

  pipeline :oidc_browser do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug KeystonePhoenixWeb.Plugs.ApiKeyAuthenticate
    plug KeystonePhoenixWeb.Plugs.RejectApiKey
  end

  pipeline :passkey_public do
    plug :accepts, ["json"]
    plug :fetch_session
    plug KeystonePhoenixWeb.Plugs.RejectApiKey
  end

  pipeline :passkey_registration do
    plug KeystonePhoenixWeb.Plugs.Authenticate
    plug KeystonePhoenixWeb.Plugs.RequireMfaStepUp
  end

  pipeline :protected_profile_resources do
    plug KeystonePhoenixWeb.Plugs.Authenticate
  end

  # 所有 HTTP API 使用与 Keystone Native 相同的 /api/v1 外部前缀。
  scope "/", KeystonePhoenixWeb do
    pipe_through :browser

    live "/", LoginLive, :index
    get "/profile/avatar/*path", ResourceController, :avatar
  end

  scope "/", KeystonePhoenixWeb do
    pipe_through [:browser, :protected_profile_resources]

    get "/profile/*path", ResourceController, :show
  end

  scope "/api/v1", KeystonePhoenixWeb do
    pipe_through :oidc_browser

    get "/auth/oidc/authorize", OidcController, :authorize
    get "/auth/oidc/callback", OidcController, :callback
  end

  scope "/api/v1/auth/passkey", KeystonePhoenixWeb do
    pipe_through :passkey_public

    post "/authentication/challenge", PasskeyController, :authentication_challenge
    post "/authentication", PasskeyController, :authentication
  end

  scope "/api/v1/auth/passkey", KeystonePhoenixWeb do
    pipe_through [:passkey_public, :passkey_registration]

    post "/registration/challenge", PasskeyController, :registration_challenge
    post "/registration", PasskeyController, :registration
  end

  scope "/api/v1", KeystonePhoenixWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/health/ready", HealthController, :readiness
    get "/file/download", FileController, :download
    post "/file/upload", FileController, :upload
    post "/file/uploads", FileController, :uploads
    get "/monitor/cacheInfo", MonitorController, :cache_info
    get "/monitor/serverInfo", MonitorController, :server_info
    get "/monitor/onlineUsers", MonitorController, :online_users
    get "/monitor/security", MonitorController, :security_metrics
    get "/monitor/security/report", MonitorController, :security_report
    delete "/monitor/onlineUser/:token_id", MonitorController, :logout_online_user
    get "/jobs", JobController, :list
    get "/jobs/invoke-targets", JobController, :invoke_targets
    get "/jobs/logs", JobController, :logs
    get "/jobs/:job_id", JobController, :show
    post "/jobs", JobController, :create
    put "/jobs/:job_id", JobController, :update
    put "/jobs/:job_id/status", JobController, :change_status
    post "/jobs/:job_id/trigger", JobController, :run
    delete "/jobs", JobController, :delete
    get "/auth/rsa-public-key", AuthController, :public_key
    get "/auth/config", AuthController, :config
    get "/auth/captcha", AuthController, :captcha
    post "/auth/login", AuthController, :login
    post "/auth/refresh", AuthController, :refresh
    post "/auth/logout", AuthController, :logout
    post "/auth/logout-refresh-token", AuthController, :logout_refresh_token
    post "/auth/register", AuthController, :register
    get "/auth/me", AuthController, :current_user
    get "/auth/routers", AuthController, :routers
    post "/auth/mfa/verify", AuthController, :verify_mfa
    post "/auth/mfa/enroll", AuthController, :begin_mfa_enrollment
    post "/auth/mfa/enroll/verify", AuthController, :verify_mfa_enrollment
    post "/auth/mfa/recovery-codes/rotate", AuthController, :rotate_mfa_recovery_codes
    put "/auth/mfa/policy/:user_id", AuthController, :set_mfa_policy
    post "/auth/mfa/step-up", AuthController, :begin_mfa_step_up
    post "/auth/mfa/step-up/verify", AuthController, :verify_mfa_step_up
    post "/api-keys", ApiKeyController, :create
    get "/api-keys", ApiKeyController, :index
    post "/api-keys/:id/rotate", ApiKeyController, :rotate
    delete "/api-keys/:id", ApiKeyController, :delete
    get "/dictionaries", DictionaryController, :list_types
    get "/dictionaries/types/:dict_id", DictionaryController, :show_type
    get "/dictionaries/items", DictionaryController, :list_data
    get "/dictionaries/items/:dict_code", DictionaryController, :show_data
    get "/dictionaries/:dict_type/items", DictionaryController, :list_data_by_type
    post "/dictionaries", DictionaryController, :create_type
    put "/dictionaries/types/:dict_id", DictionaryController, :update_type
    delete "/dictionaries/types/:dict_id", DictionaryController, :delete_type
    post "/dictionaries/:dict_type/items", DictionaryController, :create_data
    put "/dictionaries/items/:dict_code", DictionaryController, :update_data
    delete "/dictionaries/items/:dict_code", DictionaryController, :delete_data
    get "/configs", ConfigController, :list
    get "/configs/:config_id", ConfigController, :show
    post "/configs", ConfigController, :create
    put "/configs/:config_id", ConfigController, :update
    delete "/configs/:config_id", ConfigController, :delete
    get "/users", UserController, :list
    get "/users/export", UserController, :export
    post "/users/import", UserController, :import
    get "/users/import-template", UserController, :template
    get "/users/:user_id", UserController, :show
    post "/users", UserController, :create
    put "/users/:user_id", UserController, :update
    delete "/users", UserController, :delete
    delete "/users/:user_id", UserController, :delete_single
    put "/users/:user_id/password", UserController, :reset_password
    put "/users/:user_id/status", UserController, :change_status
    get "/departments", DepartmentController, :list
    get "/departments/dropdown", DepartmentController, :dropdown
    get "/departments/:dept_id", DepartmentController, :show
    post "/departments", DepartmentController, :create
    put "/departments/:dept_id", DepartmentController, :update
    delete "/departments/:dept_id", DepartmentController, :delete
    get "/posts", PostController, :list
    get "/posts/export", PostController, :export
    get "/posts/:post_id", PostController, :show
    post "/posts", PostController, :create
    put "/posts/:post_id", PostController, :update
    delete "/posts/:post_id", PostController, :delete
    get "/roles", RoleController, :list
    get "/roles/export", RoleController, :export
    get "/roles/:role_id", RoleController, :show
    post "/roles", RoleController, :create
    put "/roles/:role_id", RoleController, :update
    delete "/roles", RoleController, :delete
    delete "/roles/:role_id", RoleController, :delete
    put "/roles/:role_id/status", RoleController, :change_status
    put "/roles/:role_id/data-scope", RoleController, :data_scope
    put "/roles/:role_id/permissions", RoleController, :permissions
    get "/roles/:role_id/users", RoleController, :users
    put "/roles/:role_id/users", RoleController, :assign_users
    delete "/roles/:role_id/users", RoleController, :revoke_users
    get "/menus", MenuController, :list
    get "/menus/dropdown", MenuController, :dropdown
    get "/menus/:menu_id", MenuController, :show
    post "/menus", MenuController, :create
    put "/menus/:menu_id", MenuController, :update
    delete "/menus/:menu_id", MenuController, :delete
    get "/notices", NoticeController, :list
    get "/notices/:notice_id", NoticeController, :show
    post "/notices", NoticeController, :create
    put "/notices/:notice_id", NoticeController, :update
    delete "/notices", NoticeController, :delete
    delete "/notices/:notice_id", NoticeController, :delete
    get "/login-logs", LogController, :login_logs
    get "/login-logs/export", LogController, :export_login_logs
    delete "/login-logs", LogController, :delete_login_logs
    get "/operation-logs", LogController, :operation_logs
    get "/operation-logs/export", LogController, :export_operation_logs
    delete "/operation-logs", LogController, :delete_operation_logs
    get "/profile", ProfileController, :show
    put "/profile", ProfileController, :update
    put "/profile/password", ProfileController, :update_password
    put "/profile/avatar", ProfileController, :update_avatar
  end

  scope "/api/v1", KeystonePhoenixWeb do
    pipe_through :event_stream

    get "/monitor/networkStatus/stream", MonitorController, :network_status_stream
  end

  scope "/api", KeystonePhoenixWeb do
    pipe_through :api

    get "/.well-known/jwks.json", JwkController, :show
  end
end
