# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :keystone_phoenix,
  ecto_repos: [KeystonePhoenix.Repo],
  generators: [timestamp_type: :utc_datetime],
  job_scheduler_enabled: true,
  job_scheduler_interval_ms: 1_000,
  job_task_max_children: 64,
  job_execution_timeout_ms: 30_000,
  auth_session_cleanup_interval_ms: 60_000,
  monitor_snapshot_interval_ms: 1_000,
  telemetry_period_ms: 10_000,
  telemetry_console_reporter: false,
  repo_pool_queue_alert_threshold: 1,
  rate_limit_max_entries: 100_000,
  captcha_type: "math",
  file_base_dir: "uploads",
  jwt_issuer: "keystone",
  jwt_access_ttl: 1800,
  jwt_refresh_ttl: 604_800,
  jwt_private_key: nil,
  jwt_public_key: nil

# Configure the endpoint
config :keystone_phoenix, KeystonePhoenixWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: KeystonePhoenixWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: KeystonePhoenix.PubSub,
  live_view: [signing_salt: "FK/t/xni"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix, :filter_parameters, [
  "password",
  "Password",
  "token",
  "Token",
  "secret",
  "captcha",
  "Captcha"
]

# Phoenix's Accept plug uses MIME extensions as route formats. Register the
# server-sent events media type so the monitoring stream can negotiate it.
config :mime, :types, %{
  "text/event-stream" => ["sse"]
}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
