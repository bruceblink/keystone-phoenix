import Config

# Do not print debug messages in production
config :logger, level: :info

# 生产入口要求 HTTPS，浏览器会话 Cookie 只通过 HTTPS 发送。
config :keystone_phoenix, session_cookie_secure: true

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
