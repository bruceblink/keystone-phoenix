defmodule KeystonePhoenixWeb.Live.AdminEventsAccountsParams do
  @moduledoc "Normalizes LiveView user form fields before persistence."

  alias KeystonePhoenix.User.RoleMembership

  @doc "Aligns LiveView user fields with the Native user write contract."
  def normalize_user_params(params) when is_map(params) do
    params = normalize_enabled(params)
    params = normalize_department(params)

    if Map.has_key?(params, "roleCodes") do
      params
      |> role_codes()
      |> normalize_role_codes(params)
    else
      {:ok, params}
    end
  end

  defp normalize_enabled(params) do
    if Map.has_key?(params, "enabled") do
      Map.put(params, "status", if(truthy?(params["enabled"]), do: 1, else: 0))
    else
      params
    end
  end

  defp normalize_department(params) do
    if truthy?(params["clearDept"]), do: Map.put(params, "deptId", ""), else: params
  end

  defp role_codes(params) do
    case params["roleCodes"] do
      nil ->
        nil

      values when is_list(values) ->
        values |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

      value ->
        value
        |> to_string()
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  # Phoenix 复选框提交 on，直接事件测试可能提交布尔值或数字。
  defp truthy?(value), do: value in [true, 1, "1", "on"]

  # null 表示编辑时保留原角色；空数组才表示主动清空角色。
  defp normalize_role_codes(nil, params), do: {:ok, params}

  defp normalize_role_codes(codes, params) do
    case RoleMembership.resolve_role_codes(codes) do
      {:ok, _role_ids} -> {:ok, Map.put(params, "roleCodes", codes)}
      {:error, :role_codes_unsupported} -> {:error, :role_codes_unsupported}
    end
  end
end
