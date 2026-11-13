defmodule KeystonePhoenixWeb.Plugs.Authenticate do
  @moduledoc "Authenticates a Bearer access token and assigns the current user."

  import Plug.Conn

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Authz
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(conn, opts) do
    case conn.assigns[:api_key_principal] do
      principal when is_map(principal) ->
        authorize_principal(conn, principal, opts)

      _ ->
        authenticate_bearer(conn, opts)
    end
  end

  defp authenticate_bearer(conn, opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Auth.authenticate_access_token(token),
         :ok <- authorize(user, conn, opts) do
      assign(conn, :current_user, user)
    else
      reason -> render_authentication_error(conn, reason)
    end
  end

  # API Key 已在路由认证阶段建立服务主体；这里复用同一权限和数据范围判定。
  defp authorize_principal(conn, principal, opts) do
    case authorize(principal, conn, opts) do
      :ok -> assign(conn, :current_user, principal)
      reason -> render_authentication_error(conn, reason)
    end
  end

  defp render_authentication_error(conn, {:error, :forbidden}) do
    render_authentication_error(conn, {:error, :permission_denied})
  end

  defp render_authentication_error(conn, {:error, :permission_denied}) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.json(ApiResponse.error(:permission_denied, "没有操作权限"))
    |> halt()
  end

  defp render_authentication_error(conn, {:error, :data_scope_denied}) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.json(ApiResponse.error(:data_scope_denied, "没有数据权限"))
    |> halt()
  end

  defp render_authentication_error(conn, _reason) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(ApiResponse.error(:session_revoked, "登录状态已失效"))
    |> halt()
  end

  defp authorize(user, conn, opts) do
    cond do
      Keyword.get(opts, :admin, false) and not Authz.admin?(user) ->
        {:error, :forbidden}

      not permission_allowed?(user, conn, Keyword.get(opts, :permissions, %{})) ->
        {:error, :permission_denied}

      not data_scope_allowed?(user, conn, Keyword.get(opts, :data_scope, %{})) ->
        {:error, :data_scope_denied}

      true ->
        :ok
    end
  end

  defp permission_allowed?(_user, _conn, permissions) when map_size(permissions) == 0, do: true

  defp permission_allowed?(user, conn, permissions) do
    case Map.get(permissions, conn.private[:phoenix_action]) do
      nil -> false
      permission -> Authz.allowed?(user, permission, %{connection: conn})
    end
  end

  defp data_scope_allowed?(_user, _conn, scopes) when map_size(scopes) == 0, do: true

  defp data_scope_allowed?(user, conn, scopes) do
    case Map.get(scopes, conn.private[:phoenix_action]) do
      {:dept, key} ->
        Authz.scope_allowed?(user, :dept, param(conn.params, key), %{params: conn.params})

      {:user, key} ->
        Authz.scope_allowed?(user, :user, param(conn.params, key), %{params: conn.params})

      {:user_update, key} ->
        Authz.scope_allowed?(user, :user_update, param(conn.params, key), %{attrs: conn.params})

      {:users, key} ->
        Authz.scope_allowed?(user, :users, param(conn.params, key), %{params: conn.params})

      nil ->
        true

      _scope ->
        false
    end
  end

  defp param(params, key), do: Map.get(params, key, Map.get(params, String.to_atom(key)))
end
