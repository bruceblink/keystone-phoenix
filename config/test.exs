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

config :keystone_phoenix, job_scheduler_enabled: false

config :keystone_phoenix,
  mfa_master_key: Base.encode64(String.duplicate("m", 32)),
  mfa_master_key_version: 1,
  mfa_recovery_pepper: "test-only-mfa-recovery-pepper",
  mfa_challenge_lifetime_seconds: 300

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
