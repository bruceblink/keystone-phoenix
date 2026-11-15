defmodule KeystonePhoenixWeb.ManagementContract do
  @moduledoc "HTTP 管理资源 DTO 与 Native/admin-web 约定的字段适配。"

  @doc "把部门内部字段转换为 Native 部门字段。"
  def department(row) when is_map(row) do
    id = row["deptId"] || row["id"]

    %{
      "id" => id,
      "parentId" => row["parentId"],
      "code" => row["code"] || generated_code("dept", id),
      "name" => row["deptName"] || row["name"],
      "sortOrder" => row["orderNum"] || row["sortOrder"] || 0,
      "enabled" => enabled?(row["status"])
    }
  end

  @doc "把岗位内部字段转换为 Native 岗位字段。"
  def post(row) when is_map(row) do
    %{
      "id" => row["postId"] || row["id"],
      "code" => row["postCode"] || row["code"],
      "name" => row["postName"] || row["name"],
      "sortOrder" => row["postSort"] || row["sortOrder"] || 0,
      "enabled" => enabled?(row["status"])
    }
  end

  @doc "把单条菜单转换为 Native 菜单字段。"
  def menu(row) when is_map(row) do
    id = row["menuId"] || row["id"]

    %{
      "id" => id,
      "parentId" => row["parentId"],
      "code" => row["code"] || generated_code("menu", id),
      "name" => row["menuName"] || row["name"],
      "path" => nullable_string(row["path"]),
      "component" => nullable_string(row["routerName"] || row["component"]),
      "menuType" => native_menu_type(row["menuType"], row["isButton"]),
      "permission" => nullable_string(row["permission"]),
      "sortOrder" => row["sortOrder"] || row["rank"] || 0,
      "enabled" => enabled?(row["status"])
    }
  end

  @doc "把扁平菜单列表构建为 Native 菜单树。"
  def menu_tree(rows) when is_list(rows) do
    items = Enum.map(rows, &menu/1)
    ids = MapSet.new(items, & &1["id"])

    items
    |> Enum.filter(&(is_nil(&1["parentId"]) or not MapSet.member?(ids, &1["parentId"])))
    |> Enum.map(&menu_node(&1, items))
  end

  @doc "把配置内部字段转换为 Native 配置字段。"
  def config(row) when is_map(row) do
    %{
      "id" => row["configId"] || row["id"],
      "key" => row["configKey"] || row["key"],
      "value" => row["configValue"] || row["value"],
      "description" => row["remark"] || row["description"],
      "enabled" => enabled?(row["enabled"] || row["status"]),
      "updatedAt" => row["updatedAt"] || row["updateTime"] || row["createTime"]
    }
  end

  @doc "把字典类型内部字段转换为 Native 字典类型字段。"
  def dictionary_type(row) when is_map(row) do
    %{
      "id" => row["dictId"] || row["id"],
      "code" => row["dictType"] || row["code"],
      "name" => row["dictName"] || row["name"],
      "enabled" => enabled?(row["status"])
    }
  end

  @doc "把字典条目内部字段转换为 Native 字典条目字段。"
  def dictionary_item(row) when is_map(row) do
    %{
      "id" => row["dictCode"] || row["id"],
      "typeCode" => row["dictType"] || row["typeCode"],
      "value" => to_string(row["dictValue"] || row["value"] || ""),
      "label" => row["dictLabel"] || row["label"],
      "sortOrder" => row["dictSort"] || row["sortOrder"] || 0,
      "enabled" => enabled?(row["status"])
    }
  end

  @doc "把 Native 部门写入字段转换为 Phoenix 领域字段。"
  def department_params(params),
    do:
      params
      |> copy("code", "deptCode")
      |> copy("name", "deptName")
      |> copy("sortOrder", "orderNum")
      |> boolean_status()

  @doc "把 Native 岗位写入字段转换为 Phoenix 领域字段。"
  def post_params(params),
    do:
      params
      |> copy("code", "postCode")
      |> copy("name", "postName")
      |> copy("sortOrder", "postSort")
      |> boolean_status()

  @doc "把 Native 菜单写入字段转换为 Phoenix 领域字段。"
  def menu_params(params) do
    params
    # Native/admin-web 允许菜单没有组件；Phoenix 数据库字段使用空字符串保存该状态。
    |> Map.update("component", "", &(&1 || ""))
    |> copy("code", "menuCode")
    |> copy("name", "menuName")
    |> copy("component", "routerName")
    |> boolean_status()
    |> normalize_menu_type()
  end

  @doc "把 Native 配置写入字段转换为 Phoenix 领域字段。"
  def config_params(params),
    do:
      params
      |> copy("key", "configKey")
      |> copy("value", "configValue")
      |> copy("description", "remark")

  @doc "把 Native 字典类型写入字段转换为 Phoenix 领域字段。"
  def dictionary_type_params(params),
    do: params |> copy("code", "dictType") |> copy("name", "dictName") |> boolean_status()

  @doc "把 Native 字典条目写入字段转换为 Phoenix 领域字段。"
  def dictionary_item_params(params),
    do:
      params
      |> copy("typeCode", "dictType")
      |> copy("value", "dictValue")
      |> copy("label", "dictLabel")
      |> copy("sortOrder", "dictSort")
      |> boolean_status()

  defp menu_node(item, items) do
    children =
      items |> Enum.filter(&(&1["parentId"] == item["id"])) |> Enum.map(&menu_node(&1, items))

    %{"menu" => item, "children" => children}
  end

  defp copy(params, source, target) do
    if Map.has_key?(params, target) or not Map.has_key?(params, source),
      do: params,
      else: Map.put(params, target, params[source])
  end

  defp boolean_status(params) do
    case Map.fetch(params, "enabled") do
      {:ok, value} when is_boolean(value) -> Map.put(params, "status", if(value, do: 1, else: 0))
      _ -> params
    end
  end

  defp normalize_menu_type(params) do
    case Map.get(params, "menuType") do
      "BUTTON" -> params |> Map.put("menuType", 0) |> Map.put_new("isButton", true)
      "DIRECTORY" -> Map.put(params, "menuType", 2)
      "IFRAME" -> Map.put(params, "menuType", 3)
      "LINK" -> Map.put(params, "menuType", 4)
      "MENU" -> Map.put(params, "menuType", 1)
      _ -> params
    end
  end

  defp native_menu_type(_type, true), do: "BUTTON"
  defp native_menu_type(2, _button), do: "DIRECTORY"
  defp native_menu_type(3, _button), do: "IFRAME"
  defp native_menu_type(4, _button), do: "LINK"
  defp native_menu_type(_type, _button), do: "MENU"

  defp enabled?(value), do: value in [1, "1", true]
  defp nullable_string(value) when value in [nil, ""], do: nil
  defp nullable_string(value), do: value

  defp generated_code(prefix, id), do: prefix <> "-" <> String.replace(to_string(id), "-", "")
end
