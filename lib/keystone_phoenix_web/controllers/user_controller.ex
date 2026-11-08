defmodule KeystonePhoenixWeb.UserController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.Authenticate,
       [
         permissions: %{
           list: "system:user:list",
           show: "system:user:query",
           create: "system:user:add",
           update: "system:user:edit",
           delete: "system:user:remove",
           reset_password: "system:user:resetPwd",
           change_status: "system:user:edit",
           export: "system:user:export",
           import: "system:user:import"
         },
         data_scope: %{
           show: {:user, "user_id"},
           create: {:dept, "deptId"},
           update: {:user_update, "user_id"},
           delete: {:users, "user_ids"},
           reset_password: {:user, "user_id"},
           change_status: {:user, "user_id"}
         }
       ]
       when action in [
              :list,
              :show,
              :create,
              :update,
              :delete,
              :reset_password,
              :change_status,
              :export,
              :import,
              :template
            ]

  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.ExcelResponse

  @user_export_headers [
    "用户ID",
    "职位ID",
    "职位名称",
    "角色ID",
    "角色名称",
    "部门ID",
    "部门名称",
    "用户名",
    "用户昵称",
    "用户类型",
    "邮件",
    "号码",
    "性别",
    "用户头像",
    "状态",
    "IP",
    "登录时间",
    "创建者ID",
    "创建者",
    "创建时间",
    "修改者ID",
    "修改者",
    "修改时间",
    "备注"
  ]

  @user_import_headers [
    "部门ID",
    "用户名",
    "昵称",
    "邮件",
    "电话号码",
    "性别",
    "头像",
    "密码",
    "状态",
    "角色ID",
    "职位ID",
    "备注"
  ]

  @doc "Returns a paginated list of users."
  def list(conn, params) do
    json(conn, ApiResponse.ok(User.list_users(params, conn.assigns.current_user)))
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
    case User.create_user(params, conn.assigns.current_user.user_id) do
      {:ok, _user} -> conn |> put_status(:created) |> json(ApiResponse.ok())
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Updates editable fields for a local user."
  def update(conn, %{"user_id" => user_id} = params) do
    case User.update_user(user_id, params, conn.assigns.current_user.user_id) do
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
    case User.reset_password(user_id, params, conn.assigns.current_user.user_id) do
      {:ok, _user} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :unavailable} -> render_error(conn, :unavailable)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Enables or disables a local user."
  def change_status(conn, %{"user_id" => user_id, "status" => status}) do
    case User.change_status(user_id, status, conn.assigns.current_user.user_id) do
      {:ok, _user} -> json(conn, ApiResponse.ok())
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def change_status(conn, %{"user_id" => _user_id}) do
    render_error(conn, :invalid_status)
  end

  @doc "Exports all users matching the current filters."
  def export(conn, params) do
    rows =
      Excel.all_rows(&User.list_users(&1, conn.assigns.current_user), params)
      |> enrich_export_rows()

    ExcelResponse.send_xlsx(
      conn,
      "users.xlsx",
      @user_export_headers,
      Enum.map(rows, &user_export_row/1)
    )
  end

  @doc "Imports users from the first worksheet in an XLSX upload."
  def import(conn, %{"file" => %Plug.Upload{} = upload}) do
    with {:ok, rows} <- Excel.import_rows(upload.path),
         {:ok, records} <- Excel.rows_to_maps(rows) do
      json(conn, ApiResponse.ok(import_records(records, conn.assigns.current_user.user_id)))
    else
      {:error, reason} -> ExcelResponse.render_error(conn, import_error_message(reason))
    end
  end

  def import(conn, _params), do: ExcelResponse.render_error(conn, "导入文件不能为空")

  @doc "Downloads the blank user import template."
  def template(conn, _params) do
    blank = List.duplicate("", length(@user_import_headers))
    ExcelResponse.send_xlsx(conn, "user-import-template.xlsx", @user_import_headers, [blank])
  end

  defp enrich_export_rows(rows) do
    dept_names =
      names_by_id(Department.list_depts_by_ids(ids(rows, "deptId")), :dept_id, :dept_name)

    post_names = names_by_id(Post.list_posts_by_ids(ids(rows, "postId")), :post_id, :post_name)
    role_names = names_by_id(Role.list_roles_by_ids(ids(rows, "roleId")), :role_id, :role_name)

    user_names =
      names_by_id(
        User.list_users_by_ids(ids(rows, "creatorId") ++ ids(rows, "updaterId")),
        :user_id,
        :username
      )

    Enum.map(rows, fn row ->
      row
      |> Map.put("deptName", Map.get(dept_names, row["deptId"], ""))
      |> Map.put("postName", Map.get(post_names, row["postId"], ""))
      |> Map.put("roleName", Map.get(role_names, row["roleId"], ""))
      |> Map.put("creatorName", Map.get(user_names, row["creatorId"], ""))
      |> Map.put("updaterName", Map.get(user_names, row["updaterId"], ""))
    end)
  end

  defp user_export_row(row) do
    Enum.map(
      [
        "userId",
        "postId",
        "postName",
        "roleId",
        "roleName",
        "deptId",
        "deptName",
        "username",
        "nickname",
        "userType",
        "email",
        "phoneNumber",
        "sex",
        "avatar",
        "status",
        "loginIp",
        "loginDate",
        "creatorId",
        "creatorName",
        "createTime",
        "updaterId",
        "updaterName",
        "updateTime",
        "remark"
      ],
      &Map.get(row, &1)
    )
  end

  defp import_records(records, actor_id) do
    {success, failed} =
      records
      |> Enum.with_index(2)
      |> Enum.reduce({0, []}, fn {record, row_number}, {success, failed} ->
        case User.create_user(normalize_import_params(record), actor_id) do
          {:ok, _user} -> {success + 1, failed}
          {:error, reason} -> {success, [import_failure(row_number, record, reason) | failed]}
        end
      end)

    %{"total" => length(records), "success" => success, "failed" => Enum.reverse(failed)}
  end

  defp normalize_import_params(record) do
    Enum.reduce(["deptId", "sex", "status", "roleId", "postId"], record, fn key, result ->
      Map.update(result, key, nil, &integer_value/1)
    end)
  end

  defp integer_value(nil), do: nil
  defp integer_value(value) when is_integer(value), do: value
  defp integer_value(value) when is_float(value), do: trunc(value)

  defp integer_value(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} -> number
      _ -> value
    end
  end

  defp integer_value(value), do: value

  defp import_failure(row_number, record, reason) do
    %{
      "row" => row_number,
      "username" => Map.get(record, "username", ""),
      "reason" => failure_reason(reason)
    }
  end

  defp failure_reason(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end

  defp failure_reason(reason), do: to_string(reason)

  defp ids(rows, key), do: rows |> Enum.map(&Map.get(&1, key)) |> Enum.reject(&is_nil/1)

  defp names_by_id(records, id_key, name_key),
    do: Map.new(records, &{Map.fetch!(&1, id_key), Map.fetch!(&1, name_key)})

  defp import_error_message(:invalid_headers), do: "Excel 表头无效"
  defp import_error_message(:empty_sheet), do: "Excel 工作表为空"
  defp import_error_message(:invalid_workbook), do: "Excel 文件无效或超过大小限制"

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

  defp render_error(conn, :unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(50301, "认证会话暂不可用"))
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
