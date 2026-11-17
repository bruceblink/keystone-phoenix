defmodule KeystonePhoenix.Auth.Mfa.RecentAuthentication do
  @moduledoc """
  核验敏感操作所需的最近 MFA 认证。

  只接受当前有效会话中 600 秒内完成的 TOTP 或恢复码认证；Passkey 的 `webauthn`
  AMR 不满足此条件。数据库读取失败单独返回 unavailable，供 REST 保留 503 语义。
  """

  alias KeystonePhoenix.Auth.Mfa
  alias KeystonePhoenix.Auth.SessionAccess

  @allowed_methods ["otp", "recovery"]

  @doc "按 MFA 策略、强制选项和首次 enrollment 例外检查当前令牌。"
  def check(claims, enforce?, allow_initial_enrollment?)
      when is_map(claims) and is_boolean(enforce?) and is_boolean(allow_initial_enrollment?) do
    case Mfa.status(claims["sub"]) do
      {:ok, status} -> check_status(status, claims, enforce?, allow_initial_enrollment?)
      {:error, :unavailable} -> :unavailable
      {:error, _reason} -> :required
    end
  rescue
    _error -> :unavailable
  end

  def check(_claims, _enforce?, _allow_initial_enrollment?), do: :required

  defp check_status(%{enabled: false}, _claims, _enforce?, true), do: :allowed

  defp check_status(%{required: false}, _claims, false, _allow_initial_enrollment?),
    do: :allowed

  defp check_status(status, claims, _enforce?, _allow_initial_enrollment?) do
    if status.enabled and valid_token_amr?(claims) do
      check_current_session(claims)
    else
      :required
    end
  end

  defp valid_token_amr?(claims) do
    claims["aal"] == "AAL2" and
      Enum.any?(List.wrap(claims["amr"]), &(&1 in @allowed_methods))
  end

  defp check_current_session(claims) do
    with user_id when is_binary(user_id) <- claims["sub"],
         session_id when is_binary(session_id) <- claims["sid"],
         client_id when is_binary(client_id) <- claims["client_id"],
         access_token_id when is_binary(access_token_id) <- claims["jti"],
         {:ok, true} <-
           SessionAccess.recent_mfa_authentication?(
             user_id,
             session_id,
             client_id,
             access_token_id
           ) do
      :allowed
    else
      {:ok, false} -> :required
      {:error, :unavailable} -> :unavailable
      _ -> :required
    end
  end
end
