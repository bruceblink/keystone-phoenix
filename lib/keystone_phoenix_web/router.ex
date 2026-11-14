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
    delete "/monitor/onlineUser/:token_id", MonitorController, :logout_online_user
    get "/system/jobs", JobController, :list
    get "/system/jobs/invoke-targets", JobController, :invoke_targets
    get "/system/jobs/logs", JobController, :logs
    get "/system/jobs/:job_id", JobController, :show
    post "/system/jobs", JobController, :create
    put "/system/jobs/:job_id", JobController, :update
    put "/system/jobs/:job_id/status", JobController, :change_status
    post "/system/jobs/:job_id/run", JobController, :run
    post "/system/jobs/:job_id/cancel", JobController, :cancel
    delete "/system/jobs", JobController, :delete
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
    delete "/system/dict/cache", DictionaryController, :refresh_cache
    get "/system/configs", ConfigController, :list
    get "/system/config/:config_id", ConfigController, :show
    post "/system/config", ConfigController, :create
    put "/system/config/:config_id", ConfigController, :update
    delete "/system/configs/cache", ConfigController, :refresh_cache
    get "/system/users", UserController, :list
    get "/system/users/excel", UserController, :export
    post "/system/users/excel", UserController, :import
    get "/system/users/excelTemplate", UserController, :template
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
    get "/system/post/excel", PostController, :export
    put "/system/post", PostController, :update
    get "/system/post/:post_id", PostController, :show
    post "/system/post", PostController, :create
    put "/system/post/:post_id", PostController, :update
    delete "/system/post", PostController, :delete
    get "/system/role/list", RoleController, :list
    post "/system/role/export", RoleController, :export
    get "/system/role/:role_id", RoleController, :show
    post "/system/role", RoleController, :create
    put "/system/role", RoleController, :update
    delete "/system/roles", RoleController, :delete
    delete "/system/role/:role_id", RoleController, :delete
    put "/system/role/:role_id/status", RoleController, :change_status
    put "/system/role/:role_id/dataScope", RoleController, :data_scope
    get "/system/role/:role_id/allocated/list", RoleController, :allocated_users
    get "/system/role/:role_id/unallocated/list", RoleController, :unallocated_users
    delete "/system/role/users/:user_ids/grant/bulk", RoleController, :unassign_users
    post "/system/role/:role_id/users/:user_ids/grant/bulk", RoleController, :assign_users
    get "/system/menus", MenuController, :list
    get "/system/menus/dropdown", MenuController, :dropdown
    get "/system/menus/:menu_id", MenuController, :show
    post "/system/menus", MenuController, :create
    put "/system/menus/:menu_id", MenuController, :update
    delete "/system/menus/:menu_id", MenuController, :delete
    get "/system/notices", NoticeController, :list
    get "/system/notices/database/slave", NoticeController, :list_slave
    get "/system/notices/:notice_id", NoticeController, :show
    post "/system/notices", NoticeController, :create
    put "/system/notices/:notice_id", NoticeController, :update
    delete "/system/notices", NoticeController, :delete
    get "/logs/loginLogs", LogController, :login_logs
    get "/logs/loginLogs/excel", LogController, :export_login_logs
    delete "/logs/loginLogs", LogController, :delete_login_logs
    get "/logs/operationLogs", LogController, :operation_logs
    get "/logs/operationLogs/excel", LogController, :export_operation_logs
    delete "/logs/operationLogs", LogController, :delete_operation_logs
    get "/system/user/profile", ProfileController, :show
    put "/system/user/profile", ProfileController, :update
    put "/system/user/profile/password", ProfileController, :update_password
    post "/system/user/profile/avatar", ProfileController, :update_avatar
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
