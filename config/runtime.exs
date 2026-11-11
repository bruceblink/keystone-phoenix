import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/keystone_phoenix start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :keystone_phoenix, KeystonePhoenixWeb.Endpoint, server: true
end

parse_integer_env = fn name, default, min, max ->
  raw = System.get_env(name, Integer.to_string(default))

  case Integer.parse(raw) do
    {value, ""} when value >= min and value <= max ->
      value

    _ ->
      raise "environment variable #{name} must be an integer in #{min}..#{max}"
  end
end

config :keystone_phoenix, KeystonePhoenixWeb.Endpoint,
  http: [port: parse_integer_env.("PORT", 4000, 1, 65_535)]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  allow_insecure_database =
    System.get_env("DATABASE_SSL_ALLOW_INSECURE", "false") in ["true", "1"]

  database_ssl =
    case System.get_env("DATABASE_SSL") do
      nil ->
        true

      value when value in ["true", "1"] ->
        true

      value when value in ["false", "0"] and allow_insecure_database ->
        false

      value when value in ["false", "0"] ->
        raise "DATABASE_SSL=false requires DATABASE_SSL_ALLOW_INSECURE=true"

      value ->
        raise "DATABASE_SSL must be true or false, got #{inspect(value)}"
    end

  database_ssl_opts =
    if database_ssl do
      case System.get_env("DATABASE_SSL_CA") do
        ca_file when is_binary(ca_file) and ca_file != "" ->
          [verify: :verify_peer, cacertfile: ca_file]

        _ ->
          [verify: :verify_peer, cacerts: :public_key.cacerts_get()]
      end
    else
      []
    end

  config :keystone_phoenix, KeystonePhoenix.Repo,
    ssl: database_ssl,
    ssl_opts: database_ssl_opts,
    url: database_url,
    pool_size: parse_integer_env.("POOL_SIZE", 10, 1, 1_000),
    pool_count: parse_integer_env.("POOL_COUNT", 1, 1, 100),
    socket_options: maybe_ipv6

  config :keystone_phoenix,
    captcha_type: System.get_env("CAPTCHA_TYPE", "math"),
    job_scheduler_enabled: System.get_env("JOB_SCHEDULER_ENABLED", "true") in ["true", "1"],
    job_scheduler_interval_ms:
      parse_integer_env.("JOB_SCHEDULER_INTERVAL_MS", 1_000, 250, 86_400_000),
    job_task_max_children: parse_integer_env.("JOB_TASK_MAX_CHILDREN", 64, 1, 10_000),
    job_execution_timeout_ms:
      parse_integer_env.("JOB_EXECUTION_TIMEOUT_MS", 30_000, 250, 86_400_000),
    auth_session_cleanup_interval_ms:
      parse_integer_env.("AUTH_SESSION_CLEANUP_INTERVAL_MS", 60_000, 250, 86_400_000),
    monitor_snapshot_interval_ms:
      parse_integer_env.("MONITOR_SNAPSHOT_INTERVAL_MS", 1_000, 250, 86_400_000),
    telemetry_period_ms: parse_integer_env.("TELEMETRY_PERIOD_MS", 10_000, 250, 86_400_000),
    repo_pool_queue_alert_threshold:
      parse_integer_env.("REPO_POOL_QUEUE_ALERT_THRESHOLD", 1, 1, 1_000_000)

  config :keystone_phoenix,
    file_base_dir: System.get_env("FILE_BASE_DIR", "/var/lib/keystone/resources")

  jwt_private_key =
    System.get_env("JWT_PRIVATE_KEY") ||
      raise """
      environment variable JWT_PRIVATE_KEY is missing.
      Provide a PEM encoded RSA private key for RS256 token signing.
      """

  jwt_public_key = System.get_env("JWT_PUBLIC_KEY")

  config :keystone_phoenix,
    jwt_private_key: jwt_private_key,
    jwt_public_key: jwt_public_key

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :keystone_phoenix, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :keystone_phoenix, KeystonePhoenixWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :keystone_phoenix, KeystonePhoenixWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :keystone_phoenix, KeystonePhoenixWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
