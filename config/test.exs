import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :keystone_phoenix, KeystonePhoenix.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  database:
    "#{System.get_env("POSTGRES_DB", "keystone_phoenix_test")}#{System.get_env("MIX_TEST_PARTITION", "")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :keystone_phoenix,
  job_scheduler_enabled: false,
  # 测试进程使用 SQL sandbox；延后后台清理，避免独立 GenServer 在测试 owner 退出后访问数据库。
  auth_session_cleanup_interval_ms: 3_600_000,
  mfa_challenge_cleanup_interval_ms: 3_600_000,
  passkey_cleanup_interval_ms: 3_600_000,
  jwt_key_registry_cleanup_interval_ms: 3_600_000

# 密码测试值与 Native test profile 一致，不覆盖生产默认策略。
config :keystone_phoenix, :password_policy, %{
  min_length: 8,
  require_uppercase: false,
  require_lowercase: false,
  require_digit: false,
  require_special: false,
  disallowed: "test-only-disallowed"
}

config :keystone_phoenix,
  mfa_master_key: Base.encode64(String.duplicate("m", 32)),
  mfa_master_key_version: 1,
  mfa_recovery_pepper: "test-only-mfa-recovery-pepper",
  mfa_challenge_lifetime_seconds: 300,
  mfa_step_up_issue_max_requests: 10,
  mfa_step_up_issue_window_seconds: 60,
  mfa_challenge_cleanup_batch_size: 500

config :ex_unit, exclude: [:integration]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :keystone_phoenix, KeystonePhoenixWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "MUxgZaKq5NhtquEqSFnbYgI/V4WlHONWBycMZsd7gi/L10LcQUL0ksafa+evDzT9",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
