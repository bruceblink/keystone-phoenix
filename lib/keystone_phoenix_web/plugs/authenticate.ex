defmodule KeystonePhoenixWeb.Plugs.Authenticate do
  @moduledoc "Authenticates a Bearer access token and assigns the current user."

  import Plug.Conn

  alias KeystonePhoenix.Auth
  alias KeystonePhoenix.Permission
  alias KeystonePhoenixWeb.ApiResponse

  def init(opts), do: opts

  def call(conn, opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- Auth.authenticate_access_token(token),
         :ok <- authorize(user, conn, opts) do
      assign(conn, :current_user, user)
    else
      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(ApiResponse.error(40301, "需要管理员权限"))
        |> halt()

      {:error, :permission_denied} ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(ApiResponse.error(40302, "没有操作权限"))
        |> halt()

      {:error, :data_scope_denied} ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(ApiResponse.error(40303, "没有数据权限"))
        |> halt()

      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(ApiResponse.error(40101, "登录状态已过期"))
        |> halt()
    end
  end

  defp authorize(user, conn, opts) do
    cond do
      Keyword.get(opts, :admin, false) and not Map.get(user, :is_admin, false) ->
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
      nil -> true
      permission -> Map.get(user, :is_admin, false) or Permission.allowed?(user, permission)
    end
  end

  defp data_scope_allowed?(_user, _conn, scopes) when map_size(scopes) == 0, do: true

  defp data_scope_allowed?(user, conn, scopes) do
    case Map.get(scopes, conn.private[:phoenix_action]) do
      {:dept, key} -> Permission.data_scope_allowed?(user, :dept, param(conn.params, key))
      {:dept_optional, key} -> optional_dept_allowed?(user, param(conn.params, key))
      {:user, key} -> Permission.data_scope_allowed?(user, :user, param(conn.params, key))
      {:users, key} -> Permission.data_scope_users_allowed?(user, param(conn.params, key))
      nil -> true
      _scope -> false
    end
  end

  defp optional_dept_allowed?(_user, value) when value in [nil, "", 0, "0"], do: true
  defp optional_dept_allowed?(user, value), do: Permission.data_scope_allowed?(user, :dept, value)

  defp param(params, key), do: Map.get(params, key, Map.get(params, String.to_atom(key)))
end
