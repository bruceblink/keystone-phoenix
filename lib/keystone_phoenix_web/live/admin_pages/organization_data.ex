defmodule KeystonePhoenixWeb.Live.AdminPages.OrganizationData do
  @moduledoc "管理后台组织数据的加载与展示字段映射。"

  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Role

  # 加载部门列表并补充页面需要的层级信息。
  def load_depts(actor \\ nil) do
    Department.list_depts(%{}, actor)
    |> Enum.map(fn dept -> Map.put(dept, "depth", dept_depth(dept["ancestors"])) end)
  end

  # 加载角色列表并补充数据范围、状态和用户数量。
  def load_roles([]), do: load_roles_full()

  def load_roles(options) when is_list(options) do
    roles =
      Excel.all_rows(fn params ->
        case Role.list_roles(params, options) do
          {:ok, page} -> page
          {:error, _reason} -> %{rows: [], total: 0}
        end
      end)

    enrich_roles(roles)
  end

  defp load_roles_full do
    enrich_roles(Excel.all_rows(&Role.list_roles/1))
  end

  defp enrich_roles(roles) do
    user_counts = Role.user_counts(Enum.map(roles, & &1["roleId"]))

    roles
    |> Enum.map(fn role ->
      role
      |> Map.put("dataScopeStr", data_scope_label(role["dataScope"]))
      |> Map.put("statusStr", if(role["status"] == 1, do: "正常", else: "停用"))
      |> Map.put("userCount", Map.get(user_counts, role["roleId"], 0))
    end)
  end

  def data_scope_label("ALL"), do: "全部数据"
  def data_scope_label("TENANT"), do: "当前租户数据"
  def data_scope_label("CUSTOM"), do: "自定义数据"
  def data_scope_label("DEPARTMENT"), do: "本部门数据"
  def data_scope_label("DEPARTMENT_AND_CHILDREN"), do: "本部门及以下"
  def data_scope_label("SELF"), do: "仅本人数据"
  def data_scope_label("OWNER"), do: "本人拥有"
  def data_scope_label("MEMBER"), do: "成员关系"
  def data_scope_label(_scope), do: "未知"

  # 加载菜单列表并补充树深度、类型和状态文字。
  def load_menus([]), do: load_menus_full()

  def load_menus(options) when is_list(options) do
    menus =
      case Menu.list_menus(%{}, options) do
        {:ok, rows} -> rows
        {:error, _reason} -> []
      end

    menu_tree_rows(menus)
  end

  defp load_menus_full do
    menu_tree_rows(Menu.list_menus())
  end

  @doc "按父级关系展开菜单树，并为每个节点补充层级字段。"
  def menu_tree_rows(menus) when is_list(menus), do: enrich_menus(menus)

  defp enrich_menus(menus) do
    # API 可能返回整数根节点、字符串根节点或 UUID 字符串；树计算统一使用字符串键。
    by_id = Map.new(menus, &{menu_key(&1["menuId"] || &1["id"]), &1})

    menus
    |> menu_tree_order()
    |> Enum.map(fn menu ->
      code = menu["code"] || menu["menuCode"] || menu["menuId"]
      name = menu["name"] || menu["menuName"]
      component = menu["component"] || menu["routerName"]
      enabled = if Map.has_key?(menu, "enabled"), do: menu["enabled"], else: menu["status"] == 1

      menu
      |> Map.put("code", code)
      |> Map.put("menuCode", code)
      |> Map.put("name", name)
      |> Map.put("component", component)
      |> Map.put("sortOrder", menu["sortOrder"] || menu["menuSort"] || menu["rank"] || 0)
      |> Map.put("enabled", enabled)
      |> Map.put("depth", menu_depth(menu["parentId"], by_id, MapSet.new([menu["menuId"]])))
      |> Map.put("menuTypeStr", menu_type_label(menu["menuType"], menu["isButton"]))
      |> Map.put("statusStr", if(menu["status"] == 1, do: "正常", else: "停用"))
    end)
  end

  # 数据库按父级 UUID 排序时会打散树；页面按父级、排序号和 ID 重新展开，保持父子相邻。
  defp menu_tree_order(menus) do
    children = Enum.group_by(menus, &menu_key(&1["parentId"]))
    root_menus = Map.get(children, nil, [])
    {roots, visited} = walk_menu_children(root_menus, children, MapSet.new())

    leftovers =
      menus
      |> Enum.reject(&MapSet.member?(visited, menu_key(&1["menuId"] || &1["id"])))
      |> sort_menus()

    roots ++ leftovers
  end

  defp walk_menu_children(menus, children, visited) do
    Enum.reduce(sort_menus(menus), {[], visited}, fn menu, {rows, seen} ->
      id = menu_key(menu["menuId"] || menu["id"])

      if MapSet.member?(seen, id) do
        {rows, seen}
      else
        {descendants, seen} =
          walk_menu_children(Map.get(children, id, []), children, MapSet.put(seen, id))

        {rows ++ [menu | descendants], seen}
      end
    end)
  end

  defp sort_menus(menus) do
    Enum.sort_by(menus, fn menu ->
      {menu["sortOrder"] || menu["menuSort"] || menu["rank"] || 0, to_string(menu["menuId"])}
    end)
  end

  def menu_depth(parent_id, _menus, _seen) when parent_id in [nil, "", 0, "0"], do: 0

  def menu_depth(parent_id, menus, seen) do
    parent_key = menu_key(parent_id)
    seen = MapSet.new(seen, &menu_key/1)

    if is_nil(parent_key) or MapSet.member?(seen, parent_key) do
      0
    else
      case find_menu(menus, parent_id) do
        nil -> 0
        parent -> 1 + menu_depth(parent["parentId"], menus, MapSet.put(seen, parent_key))
      end
    end
  end

  def menu_type_label(_type, true), do: "按钮"
  def menu_type_label(2, _is_button), do: "目录"
  def menu_type_label(1, _is_button), do: "菜单"
  def menu_type_label(0, _is_button), do: "权限"
  def menu_type_label(_type, _is_button), do: "其他"

  defp find_menu(menus, parent_id) do
    Map.get(menus, parent_id) ||
      Map.get(menus, menu_key(parent_id)) ||
      Enum.find_value(menus, fn {key, menu} ->
        if menu_key(key) == menu_key(parent_id), do: menu
      end)
  end

  defp menu_key(value) when value in [nil, "", 0, "0"], do: nil
  defp menu_key(value), do: to_string(value)

  def dept_depth(nil), do: 0

  def dept_depth(ancestors) do
    max(length(String.split(ancestors, ",", trim: true)) - 1, 0)
  end
end
