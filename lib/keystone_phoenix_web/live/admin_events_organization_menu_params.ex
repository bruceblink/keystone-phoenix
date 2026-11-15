defmodule KeystonePhoenixWeb.Live.AdminEvents.OrganizationMenuParams do
  @moduledoc "菜单与角色表单参数的兼容转换。"

  @doc "把菜单多选树提交的 menuIds[] 转换为领域层使用的逗号字符串。"
  def normalize_role_menu_ids(params) when is_map(params) do
    menu_ids =
      params
      |> Map.get("menuIds[]", Map.get(params, "menuIds", ""))
      |> List.wrap()
      |> List.flatten()
      |> Enum.map(&String.trim(to_string(&1)))
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(",")

    Map.put(params, "menuIds", menu_ids)
  end

  @doc "把 Native 菜单字段复制到旧领域字段，兼容旧 LiveView 表单提交。"
  def normalize_menu_params(params, previous_form) when is_map(params) do
    params
    |> copy_menu_field("name", "menuName", previous_form)
    |> copy_menu_field("code", "menuCode", previous_form)
    |> copy_menu_field("component", "routerName", previous_form)
    |> copy_menu_field("sortOrder", "rank", previous_form)
  end

  defp copy_menu_field(params, source, target, previous_form) do
    source_value = Map.get(params, source)
    target_value = Map.get(params, target)

    cond do
      is_binary(target_value) and target_value != "" and
          source_value == Map.get(previous_form || %{}, source) ->
        Map.put(params, source, target_value)

      not Map.has_key?(params, source) and Map.has_key?(params, target) ->
        Map.put(params, source, target_value)

      true ->
        params
    end
  end
end
