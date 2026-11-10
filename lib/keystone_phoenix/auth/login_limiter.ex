defmodule KeystonePhoenix.Auth.LoginLimiter do
  @moduledoc "Per-identity login attempt limiter for HTTP and LiveView entry points."

  alias KeystonePhoenix.RateLimiter

  @limit 10
  @window_seconds 60
  @captcha_limit 10
  @captcha_window_seconds 60

  @type result :: :allow | {:deny, pos_integer()} | {:error, :unavailable}

  @spec check_http(String.t(), tuple()) :: result()
  def check_http(username, remote_ip) when is_binary(username) do
    check("http", username, format_ip(remote_ip))
  end

  @spec check_liveview(String.t(), tuple() | nil) :: result()
  def check_liveview(username, remote_ip \\ nil) when is_binary(username) do
    check("liveview", username, format_ip(remote_ip || "session"))
  end

  @spec check_captcha(tuple() | nil) :: result()
  def check_captcha(remote_ip) do
    key = "auth:captcha:" <> fingerprint(format_ip(remote_ip || "unknown"))
    RateLimiter.check(key, @captcha_limit, @captcha_window_seconds)
  end

  defp check(source, username, identity) do
    key = "auth:login:" <> fingerprint({source, identity, String.trim(username)})
    RateLimiter.check(key, @limit, @window_seconds)
  end

  defp fingerprint(value) do
    :crypto.hash(:sha256, :erlang.term_to_binary(value))
    |> Base.encode16(case: :lower)
  end

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip), do: inspect(ip)
end
