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

    enrich_menus(menus)
  end

  defp load_menus_full do
    enrich_menus(Menu.list_menus())
  end

  defp enrich_menus(menus) do
    by_id = Map.new(menus, &{&1["menuId"], &1})

    Enum.map(menus, fn menu ->
      menu
      |> Map.put("depth", menu_depth(menu["parentId"], by_id, MapSet.new([menu["menuId"]])))
      |> Map.put("menuTypeStr", menu_type_label(menu["menuType"], menu["isButton"]))
      |> Map.put("statusStr", if(menu["status"] == 1, do: "正常", else: "停用"))
    end)
  end

  def menu_depth(0, _menus, _seen), do: 0

  def menu_depth(parent_id, menus, seen) do
    if MapSet.member?(seen, parent_id) do
      0
    else
      case Map.get(menus, parent_id) do
        nil -> 0
        parent -> 1 + menu_depth(parent["parentId"], menus, MapSet.put(seen, parent_id))
      end
    end
  end

  def menu_type_label(_type, true), do: "按钮"
  def menu_type_label(2, _is_button), do: "目录"
  def menu_type_label(1, _is_button), do: "菜单"
  def menu_type_label(0, _is_button), do: "权限"
  def menu_type_label(_type, _is_button), do: "其他"

  def dept_depth(nil), do: 0

  def dept_depth(ancestors) do
    max(length(String.split(ancestors, ",", trim: true)) - 1, 0)
  end
end
