defmodule KeystonePhoenixWeb.NativeContract do
  @moduledoc "HTTP 层 Native DTO 适配。LiveView 继续使用 Phoenix 内部字段。"

  @doc "把 Phoenix 用户分页转换为 Native 的 items/page/size/total。"
  def users_page(%{rows: rows, total: total}, params) do
    %{items: Enum.map(rows, &user/1), page: page(params), size: size(params), total: total}
  end

  @doc "把 Phoenix 用户字段转换为 Native 用户字段。"
  def user(row) when is_map(row) do
    %{
      "id" => row["userId"] || row["id"],
      "username" => row["username"] || "",
      "displayName" => row["nickname"] || row["displayName"] || "",
      "deptId" => row["deptId"],
      "postId" => row["postId"],
      "enabled" => row["status"] in [1, "1", true],
      "email" => row["email"],
      "phoneNumber" => row["phoneNumber"],
      "sex" => row["sex"],
      "avatar" => row["avatar"],
      "loginIp" => row["loginIp"],
      "loginAt" => row["loginDate"] || row["loginAt"],
      "remark" => row["remark"],
      "roles" => role_codes(row)
    }
  end

  @doc "把 Native 用户写入字段转换为 Phoenix 内部字段。"
  def user_params(params) when is_map(params) do
    params
    |> maybe_copy("displayName", "nickname")
    |> maybe_boolean_status()
  end

  @doc "拒绝 Phoenix 无法持久化的多角色写入字段。"
  def validate_user_params(params) when is_map(params) do
    case Map.get(params, "roleCodes") do
      value when value in [nil, []] -> :ok
      [_code] -> :ok
      _value -> {:error, :role_codes_unsupported}
    end
  end

  @doc "把 Native 的 page/size 查询参数转换为 Phoenix 的分页参数。"
  def pagination_params(params) when is_map(params) do
    params
    |> maybe_copy("page", "pageNum")
    |> maybe_copy("size", "pageSize")
  end

  @doc "把 Phoenix 角色分页转换为 Native 角色数组。"
  def roles(%{rows: rows}), do: Enum.map(rows, &role/1)
  def roles(rows) when is_list(rows), do: Enum.map(rows, &role/1)

  @doc "把 Phoenix 角色字段转换为 Native 角色字段。"
  def role(row) when is_map(row) do
    %{
      "id" => row["roleId"] || row["id"],
      "code" => row["roleKey"] || row["code"] || "",
      "name" => row["roleName"] || row["name"] || "",
      "enabled" => row["status"] in [1, "1", true],
      "dataScope" => row["dataScope"] || "ALL",
      "deptScope" => row["deptIdSet"] || row["deptScope"],
      "permissions" => row["permissions"] || []
    }
  end

  @doc "把 Native 角色写入字段转换为 Phoenix 内部字段。"
  def role_params(params) when is_map(params) do
    params
    |> maybe_copy("code", "roleKey")
    |> maybe_copy("name", "roleName")
    |> maybe_boolean_status()
  end

  @doc "把角色用户分页转换为 Native 用户 ID 数组。"
  def role_user_ids(%{rows: rows}), do: Enum.map(rows, &(&1["userId"] || &1["id"]))
  def role_user_ids(rows) when is_list(rows), do: Enum.map(rows, &(&1["userId"] || &1["id"]))

  @doc "把 Phoenix 任务分页转换为 Native 任务数组。"
  def jobs(%{rows: rows}), do: Enum.map(rows, &job/1)
  def jobs(rows) when is_list(rows), do: Enum.map(rows, &job/1)

  @doc "把 Phoenix 任务字段转换为 Native 任务字段。"
  def job(row) when is_map(row) do
    %{
      "id" => row["jobId"] || row["id"],
      "code" => row["jobCode"] || row["code"] || "",
      "name" => row["jobName"] || row["name"] || "",
      "group" => row["jobGroup"] || row["group"] || "",
      "invokeTarget" => row["invokeTarget"] || "",
      "jobParams" => row["jobParams"],
      "cron" => row["cronExpression"] || row["cron"] || "",
      "concurrent" => row["concurrent"] in [1, "1", true],
      "enabled" => row["status"] in [1, "1", true],
      "remark" => row["remark"],
      "lastStatus" => row["lastStatus"],
      "lastRunAt" => row["lastRunAt"]
    }
  end

  @doc "把 Native 任务写入字段转换为 Phoenix 内部字段。"
  def job_params(params) when is_map(params) do
    params
    |> maybe_copy("code", "jobCode")
    |> maybe_copy("name", "jobName")
    |> maybe_copy("group", "jobGroup")
    |> maybe_copy("cron", "cronExpression")
    |> maybe_boolean_status()
    |> maybe_boolean_integer("concurrent")
  end

  @doc "补齐 Phoenix 创建任务所需的默认分组。"
  def job_create_params(params) when is_map(params) do
    params |> job_params() |> maybe_default("jobGroup", "DEFAULT")
  end

  @doc "把 Phoenix 任务日志分页转换为 Native 任务日志分页。"
  def job_logs_page(%{rows: rows, total: total}, params) do
    %{
      items: Enum.map(rows, &job_log/1),
      page: page(params),
      size: size(params),
      total: total,
      rows: rows
    }
  end

  def job_log(row) when is_map(row) do
    %{
      "id" => row["jobLogId"] || row["id"],
      "jobId" => row["jobId"],
      "jobCode" => row["jobCode"] || row["code"] || "",
      "jobName" => row["jobName"] || "",
      "jobGroup" => row["jobGroup"] || "",
      "invokeTarget" => row["invokeTarget"] || "",
      "jobParams" => row["jobParams"],
      "cron" => row["cronExpression"] || row["cron"] || "",
      "triggerType" => row["triggerType"],
      "status" => row["status"],
      "jobMessage" => row["jobMessage"],
      "exceptionInfo" => row["exceptionInfo"],
      "startedAt" => row["startTime"] || row["startedAt"],
      "finishedAt" => row["endTime"] || row["finishedAt"],
      "durationMs" => row["durationMs"],
      "createdAt" => row["createTime"] || row["createdAt"]
    }
  end

  @doc "返回 Native 删除响应。"
  def deleted(value) when is_boolean(value) or is_integer(value), do: %{"deleted" => value}

  defp role_codes(row) do
    case row["roleCodes"] || row["roles"] || row["roleKey"] do
      roles when is_list(roles) -> roles
      role when is_binary(role) and role != "" -> [role]
      _ -> []
    end
  end

  defp maybe_copy(params, source, target) do
    if Map.has_key?(params, target) or not Map.has_key?(params, source),
      do: params,
      else: Map.put(params, target, params[source])
  end

  defp maybe_boolean_status(params) do
    case Map.fetch(params, "enabled") do
      {:ok, enabled} when is_boolean(enabled) ->
        Map.put(params, "status", if(enabled, do: 1, else: 0))

      _ ->
        params
    end
  end

  defp maybe_boolean_integer(params, key) do
    case Map.fetch(params, key) do
      {:ok, value} when is_boolean(value) -> Map.put(params, key, if(value, do: 1, else: 0))
      _ -> params
    end
  end

  defp maybe_default(params, key, value) do
    case Map.get(params, key) do
      nil -> Map.put(params, key, value)
      "" -> Map.put(params, key, value)
      _ -> params
    end
  end

  defp page(params), do: integer_param(params, ["page", "pageNum"], 1)
  defp size(params), do: integer_param(params, ["size", "pageSize"], 20)

  defp integer_param(params, keys, default) do
    value = Enum.find_value(keys, &Map.get(params, &1))

    case Integer.parse(to_string(value || "")) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end
end
