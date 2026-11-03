defmodule KeystonePhoenixWeb.UserController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
       [admin: true]
       when action in [:list, :show, :create, :update, :delete, :reset_password, :change_status]

  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.ApiResponse

  @doc "Returns a paginated list of users."
  def list(conn, params) do
    json(conn, ApiResponse.ok(User.list_users(params)))
  end

  @doc "Returns a user without exposing its password."
  def show(conn, %{"user_id" => user_id}) do
    case User.get_user(user_id) do
      {:ok, user} -> json(conn, ApiResponse.ok(User.user_to_map(user)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Creates a local user."
  def create(conn, params) do
    case User.create_user(params) do
      {:ok, _user} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Updates editable fields for a local user."
  def update(conn, %{"user_id" => user_id} = params) do
    case User.update_user(user_id, params) do
      {:ok, _user} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Soft deletes one or more local users."
  def delete(conn, %{"user_ids" => user_ids}) do
    case User.delete_users(String.split(user_ids, ","), conn.assigns.current_user.user_id) do
      :ok -> json(conn, ApiResponse.ok())
      {:error, :invalid_ids} -> render_error(conn, :invalid_ids)
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :protected_user} -> render_error(conn, :protected_user)
      {:error, :update_failed} -> render_error(conn, :update_failed)
    end
  end

  @doc "Replaces a user's password."
  def reset_password(conn, %{"user_id" => user_id} = params) do
    case User.reset_password(user_id, params) do
      {:ok, _user} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Enables or disables a local user."
  def change_status(conn, %{"user_id" => user_id, "status" => status}) do
    case User.change_status(user_id, status) do
      {:ok, _user} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def change_status(conn, %{"user_id" => _user_id}) do
    render_error(conn, :invalid_status)
  end

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(10001, "找不到请求的用户"))
  end

  defp render_error(conn, :invalid_ids) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10003, "用户编号无效"))
  end

  defp render_error(conn, :protected_user) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10004, "当前用户或管理员不能删除"))
  end

  defp render_error(conn, :update_failed) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10005, "用户更新失败"))
  end

  defp render_error(conn, :invalid_status) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10006, "用户状态无效"))
  end

  defp render_error(conn, reason)
       when reason in [:dept_not_found, :post_not_found, :role_not_found] do
    message =
      %{
        dept_not_found: "部门不存在",
        post_not_found: "岗位不存在",
        role_not_found: "角色不存在"
      }[reason]

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(10007, message))
  end

  defp render_error(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(99999, "参数校验失败", errors))
  end
end
