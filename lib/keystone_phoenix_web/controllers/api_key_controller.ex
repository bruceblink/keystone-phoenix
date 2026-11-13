defmodule KeystonePhoenixWeb.ApiKeyController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate

  alias KeystonePhoenix.Auth.ApiKey
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Params
  alias KeystonePhoenixWeb.ApiResponse

  @doc "为当前用户签发 API Key；明文只在本次响应中返回。"
  def create(conn, params) do
    with :ok <- require_permission(conn, "api-key:create"),
         {:ok, expires_at} <- parse_expiry(params["expiresAt"]),
         {:ok, issued} <-
           ApiKey.issue(current_user_id(conn), params["name"], params["scopes"], expires_at) do
      conn |> put_status(:created) |> json(ApiResponse.ok(issue_to_map(issued)))
    else
      {:error, :permission_denied} -> render_error(conn, :permission_denied)
      {:error, :validation_failed} -> render_error(conn, :validation_failed)
      {:error, :scope_exceeds_permissions} -> render_error(conn, :permission_denied)
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "返回当前用户拥有的 API Key 元数据。"
  def index(conn, _params) do
    with :ok <- require_permission(conn, "api-key:read") do
      json(conn, ApiResponse.ok(Enum.map(ApiKey.list(current_user_id(conn)), &metadata_to_map/1)))
    else
      {:error, reason} -> render_error(conn, reason)
    end
  end

  @doc "轮换当前用户的 API Key，并撤销旧密钥。"
  def rotate(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "api-key:rotate"),
         {:ok, key_id} <- Params.parse_uuid(id),
         {:ok, issued} <- ApiKey.rotate(current_user_id(conn), key_id) do
      json(conn, ApiResponse.ok(issue_to_map(issued)))
    else
      {:error, :permission_denied} -> render_error(conn, :permission_denied)
      {:error, :validation_failed} -> render_error(conn, :validation_failed)
      {:error, :already_revoked} -> render_error(conn, :validation_failed, "API Key 已撤销")
      {:error, :not_found} -> render_error(conn, :validation_failed, "API Key 不存在")
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def rotate(conn, _params), do: render_error(conn, :validation_failed)

  @doc "撤销当前用户的 API Key。"
  def delete(conn, %{"id" => id}) do
    with :ok <- require_permission(conn, "api-key:revoke"),
         {:ok, key_id} <- Params.parse_uuid(id),
         :ok <- ApiKey.revoke(current_user_id(conn), key_id) do
      json(conn, ApiResponse.ok(%{"revoked" => true}))
    else
      {:error, :permission_denied} -> render_error(conn, :permission_denied)
      {:error, :validation_failed} -> render_error(conn, :validation_failed)
      {:error, :not_found} -> render_error(conn, :validation_failed, "API Key 不存在")
      {:error, reason} -> render_error(conn, reason)
    end
  end

  def delete(conn, _params), do: render_error(conn, :validation_failed)

  defp current_user_id(conn), do: conn.assigns.current_user.user_id

  defp require_permission(conn, permission) do
    if Authz.allowed?(conn.assigns.current_user, permission, %{connection: conn}),
      do: :ok,
      else: {:error, :permission_denied}
  end

  defp parse_expiry(nil), do: {:ok, nil}

  defp parse_expiry(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, date_time, _offset} -> {:ok, date_time}
      _ -> {:error, :validation_failed}
    end
  end

  defp parse_expiry(_value), do: {:error, :validation_failed}

  defp issue_to_map(issued) do
    %{
      "id" => issued.id,
      "name" => issued.name,
      "prefix" => issued.prefix,
      "apiKey" => issued.api_key,
      "scopes" => issued.scopes,
      "expiresAt" => format_datetime(issued.expires_at)
    }
  end

  defp metadata_to_map(metadata) do
    %{
      "id" => metadata.id,
      "name" => metadata.name,
      "prefix" => metadata.prefix,
      "scopes" => metadata.scopes,
      "expiresAt" => format_datetime(metadata.expires_at),
      "revokedAt" => format_datetime(metadata.revoked_at),
      "lastUsedAt" => format_datetime(metadata.last_used_at),
      "createdAt" => format_datetime(metadata.created_at)
    }
  end

  defp format_datetime(nil), do: nil
  defp format_datetime(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp render_error(conn, reason, message \\ nil) do
    {status, code, default_message} =
      case reason do
        :permission_denied ->
          {:forbidden, :permission_denied, "没有操作权限"}

        :authorization_unavailable ->
          {:service_unavailable, :authorization_unavailable, "授权服务暂不可用"}

        _ ->
          {:unprocessable_entity, :validation_failed, "请求参数无效"}
      end

    conn |> put_status(status) |> json(ApiResponse.error(code, message || default_message))
  end
end
