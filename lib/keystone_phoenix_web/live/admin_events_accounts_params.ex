defmodule KeystonePhoenixWeb.Live.AdminEventsAccountsParams do
  @moduledoc "Normalizes LiveView user form fields before persistence."

  alias KeystonePhoenix.Role

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
    params["roleCodes"]
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Phoenix 复选框提交 on，直接事件测试可能提交布尔值或数字。
  defp truthy?(value), do: value in [true, 1, "1", "on"]

  defp normalize_role_codes([], params),
    do: {:ok, params |> Map.put("roleId", nil) |> Map.delete("roleCodes")}

  defp normalize_role_codes([code], params), do: normalize_single_role(params, code)
  defp normalize_role_codes(_codes, _params), do: {:error, :role_codes_unsupported}

  defp normalize_single_role(params, code) do
    case Role.get_role_by_key(code) do
      {:ok, role} -> {:ok, params |> Map.put("roleId", role.role_id) |> Map.delete("roleCodes")}
      {:error, :not_found} -> {:error, :role_codes_unsupported}
    end
  end
end
