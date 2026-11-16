defmodule KeystonePhoenixWeb.AuthTokenResponse do
  @moduledoc "将内部令牌结果映射为跨项目统一的认证响应字段。"

  @doc "Returns the public token response shared with Keystone Native."
  @spec to_map(map()) :: map()
  def to_map(tokens) when is_map(tokens) do
    current_user = Map.get(tokens, :current_user, %{})
    user_info = Map.get(current_user, "userInfo", %{})
    role_key = Map.get(current_user, "roleKey")

    %{
      "accessToken" => Map.fetch!(tokens, :token),
      "refreshToken" => Map.fetch!(tokens, :refresh_token),
      "tokenType" => "Bearer",
      "expiresIn" => Map.fetch!(tokens, :expires_in),
      "refreshExpiresIn" => Map.fetch!(tokens, :refresh_expires_in),
      "username" => Map.get(user_info, "username", ""),
      "displayName" => Map.get(user_info, "nickname") || Map.get(user_info, "username", ""),
      "roles" => roles(Map.get(current_user, "roles"), role_key),
      "sessionId" => Map.fetch!(tokens, :session_id),
      "clientId" => Map.get(tokens, :client_id, "web")
    }
  end

  defp roles(role_keys, _role_key) when is_list(role_keys),
    do: Enum.uniq(Enum.filter(role_keys, &is_non_empty_string/1))

  defp roles(_role_keys, role_key) when is_binary(role_key) and role_key != "", do: [role_key]
  defp roles(_role_keys, _role_key), do: []

  defp is_non_empty_string(value), do: is_binary(value) and String.trim(value) != ""
end
