defmodule KeystonePhoenixWeb.NativeObservabilityContract do
  @moduledoc "HTTP 审计、监控和个人资料 DTO 适配。"

  alias KeystonePhoenixWeb.NativeContract

  @doc "把登录日志转换为 Native 分页记录。"
  def login_logs_page(%{rows: rows, total: total}, params) do
    %{items: Enum.map(rows, &login_log/1), page: page(params), size: size(params), total: total}
  end

  @doc "把 Phoenix 登录日志字段转换为 Native 字段。"
  def login_log(row) when is_map(row) do
    %{
      "id" => row["infoId"] || row["id"],
      "username" => row["username"] || "",
      "status" => login_status(row["status"]),
      "ipAddress" => row["ipAddress"],
      "message" => row["msg"] || row["message"],
      "userAgent" => user_agent(row),
      "loginAt" => row["loginTime"] || row["loginAt"]
    }
  end

  @doc "把操作日志转换为 Native 分页记录。"
  def operation_logs_page(%{rows: rows, total: total}, params) do
    %{
      items: Enum.map(rows, &operation_log/1),
      page: page(params),
      size: size(params),
      total: total
    }
  end

  @doc "把 Phoenix 操作日志字段转换为 Native 字段。"
  def operation_log(row) when is_map(row) do
    %{
      "id" => row["operationId"] || row["id"],
      "actorUsername" => row["username"] || row["actorUsername"] || "",
      "action" => row["businessTypeStr"] || row["action"] || "",
      "resource" => row["requestModule"] || row["resource"] || "",
      "resourceId" => row["userId"] || row["resourceId"],
      "detail" => row["operationResult"] || row["operationParam"] || row["detail"],
      "createdAt" => row["operationTime"] || row["createdAt"]
    }
  end

  @doc "把 Native 个人资料字段转换为公开用户 DTO。"
  def profile(row) when is_map(row) do
    row
    |> NativeContract.user()
    |> Map.put("mustChangePassword", row["mustChangePassword"] in [true, 1, "1"])
  end

  @doc "把 Phoenix 服务信息转换为 Native 监控字段。"
  def server_info(info) when is_map(info) do
    jvm = info["jvmInfo"] || %{}
    memory = info["memoryInfo"] || %{}
    system = info["systemInfo"] || %{}
    cpu = info["cpuInfo"] || %{}

    %{
      "javaVersion" => jvm["version"] || "",
      "jvmName" => jvm["name"] || "BEAM",
      "osName" => system["osName"] || "",
      "osVersion" => system["osArch"] || "",
      "processors" => cpu["cpuNum"] || 0,
      "maxMemory" => megabytes_to_bytes(jvm["max"] || memory["total"]),
      "totalMemory" => megabytes_to_bytes(jvm["total"] || memory["total"]),
      "freeMemory" => megabytes_to_bytes(jvm["free"] || memory["free"]),
      "heapUsed" => megabytes_to_bytes(jvm["used"] || memory["used"]),
      "uptimeMs" => uptime_ms(jvm["runTime"])
    }
  end

  @doc "把 Phoenix 缓存统计转换为 Native 字段。"
  def cache_info(info) when is_map(info) do
    %{
      "provider" => info["backend"] || "ets",
      "activeSessions" => info["activeSessions"] || 0,
      "loginLogEntries" => info["loginLogEntries"] || info["cacheEntries"] || 0
    }
  end

  @doc "把在线会话分页转换为 Native 字段。"
  def online_users_page(%{rows: rows, total: total}, params) do
    %{
      items: Enum.map(rows, &online_user/1),
      page: page(params),
      size: size(params),
      total: total
    }
  end

  @doc "把 Phoenix 在线会话字段转换为 Native 字段。"
  def online_user(row) when is_map(row) do
    %{
      "sessionId" => row["sessionId"] || row["tokenId"] || row["id"],
      "userId" => row["userId"],
      "username" => row["username"] || "",
      "displayName" => row["displayName"] || row["nickname"] || "",
      "ipAddress" => row["ipAddress"],
      "createdAt" => row["createdAt"] || row["loginTime"],
      "expiresAt" => row["expiresAt"] || row["loginTime"],
      "accessExpiresAt" => row["accessExpiresAt"] || row["expiresAt"] || row["loginTime"]
    }
  end

  defp login_status(status) when status in [1, "1"], do: "SUCCESS"
  defp login_status(status) when status in [2, "2"], do: "LOGOUT"
  defp login_status(status) when status in [3, "3"], do: "REGISTER"
  defp login_status(_status), do: "FAILURE"

  defp user_agent(row) do
    [row["browser"], row["operationSystem"]]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join(" / ")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp megabytes_to_bytes(value) when is_integer(value) or is_float(value),
    do: round(value * 1_048_576)

  defp megabytes_to_bytes(_value), do: 0

  defp uptime_ms(value) when is_binary(value) do
    case Regex.run(~r/^(?:(\d+)d )?(?:(\d+)h )?(?:(\d+)m )?(\d+)s$/, value,
           capture: :all_but_first
         ) do
      [days, hours, minutes, seconds] ->
        (((integer(days) * 24 + integer(hours)) * 60 + integer(minutes)) * 60 + integer(seconds)) *
          1_000

      _ ->
        0
    end
  end

  defp uptime_ms(_value), do: 0
  defp integer(nil), do: 0
  defp integer(value), do: String.to_integer(value)
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
