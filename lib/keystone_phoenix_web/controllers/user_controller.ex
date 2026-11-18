defmodule KeystonePhoenixWeb.UserController do
  use KeystonePhoenixWeb, :controller

  plug KeystonePhoenixWeb.Plugs.RejectApiKey
       when action in [:create, :import, :delete, :delete_single, :reset_password]

  # 普通用户写操作遵循账号 MFA 策略；用户导入始终要求 AAL2。
  plug KeystonePhoenixWeb.Plugs.RequireMfaStepUp
       when action in [
              :create,
              :update,
              :delete,
              :delete_single,
              :reset_password,
              :change_status
            ]

  plug KeystonePhoenixWeb.Plugs.RequireMfaStepUp, [enforce: true] when action in [:import]

  plug KeystonePhoenixWeb.Plugs.Authenticate,
       [
         permissions: %{
           list: "user:read",
           show: "user:read",
           create: "user:create",
           update: "user:update",
           delete: "user:delete",
           delete_single: "user:delete",
           reset_password: "user:reset-password",
           change_status: "user:update",
           export: "user:export",
           import: "user:import"
         },
         data_scope: %{
           show: {:user, "user_id"},
           create: {:dept, "deptId"},
           update: {:user_update, "user_id"},
           delete: {:users, "ids"},
           delete_single: {:user, "user_id"},
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
              :delete_single,
              :reset_password,
              :change_status,
              :export,
              :import
            ]

  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User
  alias KeystonePhoenixWeb.ApiResponse
  alias KeystonePhoenixWeb.ExcelResponse
  alias KeystonePhoenixWeb.NativeContract

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

  @doc "Returns a paginated list of users."
  def list(conn, params) do
    page = User.list_users(NativeContract.pagination_params(params), conn.assigns.current_user)
    json(conn, ApiResponse.ok(NativeContract.users_page(page, params)))
  end

  @doc "Returns a user without exposing its password."
  def show(conn, %{"user_id" => user_id}) do
    case User.get_user(user_id) do
      {:ok, user} -> json(conn, ApiResponse.ok(native_user(user)))
      {:error, :not_found} -> render_error(conn, :not_found)
    end
  end

  @doc "Creates a local user."
  def create(conn, params) do
    case native_user_params(params) do
      {:ok, attrs} ->
        if Authz.role_assignment_allowed?(conn.assigns.current_user, role_id_param(attrs)) do
          case User.create_user(attrs,
                 authorization: %{
                   principal: conn.assigns.current_user,
                   permission: "user:create"
                 }
               ) do
            {:ok, user} ->
              conn |> put_status(:created) |> json(ApiResponse.ok(native_user(user)))

            {:error, changeset} ->
              render_error(conn, changeset)
          end
        else
          render_error(conn, :role_assignment_forbidden)
        end

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Updates editable fields for a local user."
  def update(conn, %{"user_id" => user_id} = params) do
    case native_user_params(params, :update) do
      {:ok, attrs} ->
        if Authz.role_assignment_allowed?(conn.assigns.current_user, role_id_param(attrs)) do
          case User.update_user(user_id, attrs,
                 authorization: %{
                   principal: conn.assigns.current_user,
                   permission: "user:update"
                 }
               ) do
            {:ok, user} -> json(conn, ApiResponse.ok(native_user(user)))
            {:error, :not_found} -> render_error(conn, :not_found)
            {:error, changeset} -> render_error(conn, changeset)
          end
        else
          render_error(conn, :role_assignment_forbidden)
        end

      {:error, reason} ->
        render_error(conn, reason)
    end
  end

  @doc "Soft deletes one or more local users."
  def delete(conn, %{"ids" => ids}), do: delete_users(conn, ids, false)

  def delete(conn, %{"user_id" => user_id}), do: delete_users(conn, user_id, true)

  def delete(conn, _params), do: render_error(conn, :invalid_ids)

  def delete_single(conn, %{"user_id" => user_id}), do: delete_users(conn, user_id, true)

  defp delete_users(conn, user_ids, single?) do
    # 与 Native 一致，批量编号允许逗号两侧的空格。
    ids = user_ids |> String.split(",") |> Enum.map(&String.trim/1)

    case User.delete_users(ids,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "user:delete"
           }
         ) do
      :ok ->
        count =
          user_ids |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.uniq() |> length()

        json(conn, ApiResponse.ok(%{"deleted" => if(single?, do: true, else: count)}))

      {:error, :invalid_ids} ->
        render_error(conn, :invalid_ids)

      {:error, :not_found} ->
        render_error(conn, :not_found)

      {:error, :protected_user} ->
        render_error(conn, :protected_user)

      {:error, :update_failed} ->
        render_error(conn, :update_failed)
    end
  end

  @doc "Replaces a user's password."
  def reset_password(conn, %{"user_id" => user_id} = params) do
    case User.reset_password(user_id, NativeContract.user_params(params),
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "user:reset-password"
           }
         ) do
      {:ok, user} -> json(conn, ApiResponse.ok(native_user(user)))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, :unavailable} -> render_error(conn, :unavailable)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  @doc "Enables or disables a local user."
  def change_status(conn, %{"user_id" => user_id, "enabled" => enabled})
      when is_boolean(enabled) do
    change_status(conn, %{"user_id" => user_id, "status" => if(enabled, do: 1, else: 0)})
  end

  def change_status(conn, %{"user_id" => user_id, "status" => status}) do
    case User.change_status(user_id, status,
           authorization: %{
             principal: conn.assigns.current_user,
             permission: "user:update"
           }
         ) do
      {:ok, user} -> json(conn, ApiResponse.ok(native_user(user)))
      {:error, :not_found} -> render_error(conn, :not_found)
      {:error, changeset} -> render_error(conn, changeset)
    end
  end

  def change_status(conn, %{"user_id" => _user_id}) do
    render_error(conn, :invalid_status)
  end

  defp native_user(user) do
    legacy = User.user_to_map_with_relations(user)
    NativeContract.user(legacy)
  end

  defp native_user_params(params), do: native_user_params(params, :standard)

  defp native_user_params(params, :update) do
    with :ok <- NativeContract.validate_user_update_params(params) do
      {:ok, NativeContract.user_update_params(params)}
    end
  end

  defp native_user_params(params, _mode) do
    with :ok <- NativeContract.validate_user_params(params) do
      {:ok, NativeContract.user_params(params)}
    end
  end

  @doc "Exports all users matching the current filters."
  def export(conn, params) do
    case export_workbook(params, conn.assigns.current_user) do
      {:ok, binary} -> ExcelResponse.send_xlsx(conn, "users.xlsx", binary)
      {:error, _reason} -> ExcelResponse.render_error(conn, "Excel 导出失败")
    end
  end

  @doc "Builds the authorized user workbook for HTTP and LiveView downloads."
  def export_workbook(params, actor) when is_map(params) and is_map(actor) do
    rows = Excel.all_rows(&User.list_users(&1, actor), params) |> enrich_export_rows()
    Excel.export(@user_export_headers, Enum.map(rows, &user_export_row/1), "users.xlsx")
  end

  @doc "Imports users from the first worksheet in an XLSX upload."
  def import(conn, %{"file" => %Plug.Upload{} = upload}) do
    case import_file(upload.path, upload.filename, conn.assigns.current_user) do
      {:ok, result} -> json(conn, ApiResponse.ok(result))
      {:error, reason} -> ExcelResponse.render_error(conn, import_error_message(reason))
    end
  end

  def import(conn, _params), do: ExcelResponse.render_error(conn, "导入文件不能为空")

  @doc "Imports one uploaded XLSX file with the existing row and scope checks."
  def import_file(path, filename, actor)
      when is_binary(path) and is_binary(filename) and is_map(actor) do
    with {:ok, rows} <- Excel.import_rows(path, filename),
         {:ok, records} <- Excel.rows_to_maps(rows) do
      {:ok, import_records(records, actor)}
    end
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

  defp import_records(records, actor) do
    {success, failed} =
      records
      |> Enum.with_index(2)
      |> Enum.reduce({0, []}, fn {record, row_number}, {success, failed} ->
        record = normalize_import_params(record)

        case import_authorized?(record, actor) do
          :ok ->
            case User.create_user(record,
                   authorization: %{
                     principal: actor,
                     permission: "user:import"
                   }
                 ) do
              {:ok, _user} -> {success + 1, failed}
              {:error, reason} -> {success, [import_failure(row_number, record, reason) | failed]}
            end

          {:error, reason} ->
            {success, [import_failure(row_number, record, reason) | failed]}
        end
      end)

    %{"total" => length(records), "success" => success, "failed" => Enum.reverse(failed)}
  end

  defp normalize_import_params(record) do
    Enum.reduce(["deptId", "sex", "status", "roleId", "postId"], record, fn key, result ->
      Map.update(result, key, nil, &integer_value/1)
    end)
  end

  defp import_authorized?(record, actor) do
    cond do
      not Authz.scope_allowed?(actor, :dept, record["deptId"]) ->
        {:error, :data_scope_denied}

      not Authz.role_assignment_allowed?(actor, role_id_param(record)) ->
        {:error, :role_assignment_forbidden}

      true ->
        :ok
    end
  end

  defp role_id_param(params),
    do: Map.get(params, "roleCodes", Map.get(params, "roleId", Map.get(params, :role_id)))

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
    if username_already_exists?(changeset) do
      "username already exists"
    else
      changeset
      |> Ecto.Changeset.traverse_errors(&format_import_validation_message/1)
      |> Enum.flat_map(fn {field, messages} ->
        Enum.map(List.wrap(messages), &"#{import_error_field(field)}：#{&1}")
      end)
      |> Enum.join("；")
      |> case do
        "" -> "用户数据无效"
        message -> message
      end
    end
  end

  defp failure_reason(:data_scope_denied), do: "没有数据权限"
  defp failure_reason(:role_assignment_forbidden), do: "没有角色分配权限"
  defp failure_reason(reason), do: to_string(reason)

  # 管理端约定每条失败原因都是字符串；重复用户名沿用 Native 的公开原因。
  defp username_already_exists?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:username, {"has already been taken", _opts}} -> true
      _error -> false
    end)
  end

  # 保留 Changeset 的字段约束说明，并把长度等动态参数展开为可读文本。
  defp format_import_validation_message({message, opts}) do
    Regex.replace(~r"%{(\w+)}", message, fn _, key ->
      case Enum.find(opts, fn {option, _value} -> Atom.to_string(option) == key end) do
        {_option, value} -> to_string(value)
        nil -> "%{#{key}}"
      end
    end)
  end

  # 用中文字段名给导入失败明细提供定位信息。
  defp import_error_field(:username), do: "用户名"
  defp import_error_field(:nickname), do: "昵称"
  defp import_error_field(:password), do: "密码"
  defp import_error_field(:email), do: "邮箱"
  defp import_error_field(:phone_number), do: "联系电话"
  defp import_error_field(:sex), do: "性别"
  defp import_error_field(:status), do: "状态"
  defp import_error_field(:avatar), do: "头像"
  defp import_error_field(:remark), do: "备注"
  defp import_error_field(field), do: Atom.to_string(field)

  defp ids(rows, key), do: rows |> Enum.map(&Map.get(&1, key)) |> Enum.reject(&is_nil/1)

  defp names_by_id(records, id_key, name_key),
    do: Map.new(records, &{Map.fetch!(&1, id_key), Map.fetch!(&1, name_key)})

  defp import_error_message(:invalid_headers), do: "Excel 表头无效"
  defp import_error_message(:empty_sheet), do: "Excel 工作表为空"
  defp import_error_message(:invalid_workbook), do: "Excel 文件无效或超过大小限制"

  defp render_error(conn, :not_found) do
    conn
    |> put_status(:not_found)
    |> json(ApiResponse.error(:resource_not_found, "找不到请求的用户"))
  end

  defp render_error(conn, :invalid_ids) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "用户编号无效"))
  end

  defp render_error(conn, :protected_user) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "当前用户或管理员不能删除"))
  end

  defp render_error(conn, :update_failed) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "用户更新失败"))
  end

  defp render_error(conn, :unavailable) do
    conn
    |> put_status(:service_unavailable)
    |> json(ApiResponse.error(:authorization_unavailable, "认证会话暂不可用"))
  end

  defp render_error(conn, :invalid_status) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "用户状态无效"))
  end

  defp render_error(conn, :role_assignment_forbidden) do
    conn
    |> put_status(:forbidden)
    |> json(ApiResponse.error(:permission_denied, "没有角色分配权限"))
  end

  defp render_error(conn, :role_codes_unsupported) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "角色编码无效、不存在或已停用"))
  end

  defp render_error(conn, :invalid_dept_id) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "部门编号无效"))
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
    |> json(ApiResponse.error(:validation_failed, message))
  end

  defp render_error(conn, changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(ApiResponse.error(:validation_failed, "参数校验失败", errors))
  end
end
