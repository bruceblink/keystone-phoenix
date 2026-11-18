defmodule KeystonePhoenixWeb.ErrorCatalog do
  @moduledoc """
  跨项目业务错误码目录。

  status 记录现有 HTTP 状态约定，错误码用于日志、接口响应和排错索引。
  目录不会根据可读消息猜测错误码；每个业务条件必须在边界层显式选择一个代码。
  legacy 代码只用于兼容尚未迁移的旧认证入口，新增代码不得继续使用它们。
  """

  @entries %{
    "authentication_required" => %{status: 401, retryable: false, message_key: "auth.required"},
    "invalid_credential" => %{
      status: 401,
      retryable: false,
      message_key: "auth.invalid_credentials"
    },
    "mfa_required" => %{status: 401, retryable: false, message_key: "auth.mfa_required"},
    "mfa_invalid_code" => %{
      status: 401,
      retryable: false,
      message_key: "auth.mfa_invalid_code"
    },
    "mfa_step_up_required" => %{
      status: 403,
      retryable: false,
      message_key: "auth.mfa_step_up_required"
    },
    "mfa_state_conflict" => %{
      status: 409,
      retryable: false,
      message_key: "auth.mfa_state_conflict"
    },
    "mfa_challenge_invalid" => %{
      status: 401,
      retryable: false,
      message_key: "auth.mfa_challenge_invalid"
    },
    "active_session_conflict" => %{
      status: 409,
      retryable: false,
      message_key: "auth.active_session_conflict"
    },
    "permission_denied" => %{status: 403, retryable: false, message_key: "auth.permission_denied"},
    "data_scope_denied" => %{status: 403, retryable: false, message_key: "auth.data_scope_denied"},
    "session_revoked" => %{status: 401, retryable: false, message_key: "auth.session_revoked"},
    "resource_not_found" => %{status: 404, retryable: false, message_key: "resource.not_found"},
    "resource_conflict" => %{status: 409, retryable: false, message_key: "resource.conflict"},
    # 角色删除保持 422，并按成员关系与系统保护分别登记错误码。
    "role_has_members" => %{status: 422, retryable: false, message_key: "role.has_members"},
    "role_protected" => %{status: 422, retryable: false, message_key: "role.protected"},
    "rate_limited" => %{status: 429, retryable: true, message_key: "request.rate_limited"},
    "precondition_required" => %{
      status: 428,
      retryable: false,
      message_key: "request.precondition_required"
    },
    "payload_too_large" => %{
      status: 413,
      retryable: false,
      message_key: "request.payload_too_large"
    },
    "https_required" => %{
      status: 426,
      retryable: false,
      message_key: "request.https_required"
    },
    "validation_failed" => %{
      status: 422,
      retryable: false,
      message_key: "request.validation_failed"
    },
    "api_key_name_invalid" => %{
      status: 422,
      retryable: false,
      message_key: "error.api_key_name_invalid"
    },
    "profile_display_name_required" => %{
      status: 422,
      retryable: false,
      message_key: "error.profile_display_name_required"
    },
    "profile_avatar_required" => %{
      status: 422,
      retryable: false,
      message_key: "error.profile_avatar_required"
    },
    # 旧密码验证成功但新密码相同时，要求用户选择其他密码。
    "password_same_as_current" => %{
      status: 422,
      retryable: false,
      message_key: "error.password_same_as_current"
    },
    "api_key_expiry_invalid" => %{
      status: 422,
      retryable: false,
      message_key: "error.api_key_expiry_invalid"
    },
    "api_key_expiry_out_of_range" => %{
      status: 422,
      retryable: false,
      message_key: "error.api_key_expiry_out_of_range"
    },
    "service_unavailable" => %{status: 503, retryable: true, message_key: "service.unavailable"},
    "authorization_unavailable" => %{
      status: 503,
      retryable: true,
      message_key: "auth.unavailable",
      legacy: true
    },
    "internal_error" => %{status: 500, retryable: false, message_key: "service.internal_error"}
  }

  @doc "返回稳定错误码目录。"
  def all, do: @entries

  @doc "返回所有已登记错误码。"
  def codes, do: Map.keys(@entries)

  @doc "检查错误码是否已登记。"
  def valid?(code), do: Map.has_key?(@entries, normalize(code))

  @doc "返回错误码的排错元数据。"
  def metadata(code), do: Map.get(@entries, normalize(code))

  @doc "按错误码返回包含代码本身的完整目录项；未知代码返回 nil。"
  def lookup(code) do
    normalized = normalize(code)

    case Map.fetch(@entries, normalized) do
      {:ok, metadata} -> Map.put(metadata, :code, normalized)
      :error -> nil
    end
  end

  defp normalize(code) when is_atom(code), do: Atom.to_string(code)
  defp normalize(code) when is_binary(code), do: String.trim(code)
  defp normalize(_code), do: ""
end
