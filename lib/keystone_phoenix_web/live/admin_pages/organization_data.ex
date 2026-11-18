defmodule KeystonePhoenixWeb.Live.AdminPages.OrganizationData do
  @moduledoc "管理后台组织数据的加载与展示字段映射。"

  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Excel
  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.Permissions

  # 加载部门列表并补充页面需要的层级信息。
  def load_depts(actor \\ nil) do
    case load_depts_result(actor) do
      {:ok, rows} -> rows
      {:error, _reason} -> []
    end
  end

  @doc "读取部门列表并保留数据库或数据范围错误。"
  def load_depts_result(actor \\ nil) do
    rows = Department.list_depts(%{}, actor)
    {:ok, Enum.map(rows, fn dept -> Map.put(dept, "depth", dept_depth(dept["ancestors"])) end)}
  rescue
    _error -> {:error, :service_unavailable}
  end

  # 加载角色列表并补充数据范围、状态、用户数量和有效权限数量。
  def load_roles(options) when is_list(options) do
    case load_roles_result(options) do
      {:ok, rows} -> rows
      {:error, _reason} -> []
    end
  end

  @doc "读取角色列表并保留授权或数据库错误。"
  def load_roles_result(options) when is_list(options) do
    fetcher =
      if options == [],
        do: &Role.list_roles/1,
        else: fn params -> Role.list_roles(params, options) end

    with {:ok, roles} <- Excel.all_rows_result(fetcher) do
      {:ok, enrich_roles(roles)}
    end
  rescue
    _error -> {:error, :service_unavailable}
  end

  @doc "读取角色当前页，并返回筛选后的总数量。"
  def load_roles_page_result(options, params) when is_list(options) and is_map(params) do
    result =
      if options == [], do: Role.list_roles(params), else: Role.list_roles(params, options)

    case result do
      {:ok, %{rows: rows, total: total}} -> {:ok, %{rows: enrich_roles(rows), total: total}}
      %{rows: rows, total: total} -> {:ok, %{rows: enrich_roles(rows), total: total}}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_page}
    end
  rescue
    _error -> {:error, :service_unavailable}
  end

  def enrich_roles(roles) when is_list(roles) do
    user_counts = Role.user_counts(Enum.map(roles, & &1["roleId"]))
    permission_counts = Permissions.counts(Enum.map(roles, & &1["roleId"]))

    roles
    |> Enum.map(fn role ->
      role
      |> Map.put("dataScopeStr", data_scope_label(role["dataScope"]))
      |> Map.put("statusStr", if(role["status"] == 1, do: "正常", else: "停用"))
      |> Map.put("userCount", Map.get(user_counts, role["roleId"], 0))
      |> Map.put("permissionCount", Map.get(permission_counts, role["roleId"], 0))
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
  def load_menus(options) when is_list(options) do
    case load_menus_result(options) do
      {:ok, rows} -> rows
      {:error, _reason} -> []
    end
  end

  @doc "读取菜单树并保留授权或数据库错误。"
  def load_menus_result(options) when is_list(options) do
    result =
      if options == [], do: {:ok, Menu.list_menus(%{})}, else: Menu.list_menus(%{}, options)

    case result do
      {:ok, menus} when is_list(menus) -> {:ok, menu_tree_rows(menus)}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_page}
    end
  rescue
    _error -> {:error, :service_unavailable}
  end

  @doc "按父级关系展开菜单树，并为每个节点补充层级字段。"
  def menu_tree_rows(menus) when is_list(menus), do: enrich_menus(menus)

  @doc "将 Native 与 Phoenix 菜单返回的启用字段统一为布尔值。"
  def menu_enabled?(menu) when is_map(menu) do
    case Map.fetch(menu, "enabled") do
      {:ok, value} -> truthy_value?(value)
      :error -> truthy_value?(Map.get(menu, "status"))
    end
  end

  def menu_enabled?(_menu), do: false

  defp enrich_menus(menus) do
    # API 可能返回整数根节点、字符串根节点或 UUID 字符串；树计算统一使用字符串键。
    by_id = Map.new(menus, &{menu_key(&1["menuId"] || &1["id"]), &1})

    menus
    |> menu_tree_order()
    |> Enum.map(fn menu ->
      code = menu["code"] || menu["menuCode"] || menu["menuId"] || menu["id"]
      name = menu["name"] || menu["menuName"]
      component = menu["component"] || menu["routerName"]
      enabled = menu_enabled?(menu)
      status = if enabled, do: 1, else: 0

      menu
      |> Map.put("code", code)
      |> Map.put("menuCode", code)
      |> Map.put("name", name)
      |> Map.put("component", component)
      |> Map.put("sortOrder", menu["sortOrder"] || menu["menuSort"] || menu["rank"] || 0)
      |> Map.put("enabled", enabled)
      |> Map.put("status", status)
      |> Map.put(
        "depth",
        menu_depth(menu["parentId"], by_id, MapSet.new([menu["menuId"] || menu["id"]]))
      )
      |> Map.put("menuTypeStr", menu_type_label(menu["menuType"], menu["isButton"]))
      |> Map.put("statusStr", if(enabled, do: "正常", else: "停用"))
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

  # Native 使用字符串类型，Phoenix 数据库查询使用整数；这里统一两种编码。
  def menu_type_label(type, is_button) do
    cond do
      truthy_value?(is_button) -> "按钮"
      type in [2, "2", "DIRECTORY", "directory"] -> "目录"
      type in [1, "1", "MENU", "menu"] -> "菜单"
      type in ["BUTTON", "button"] -> "按钮"
      type in [0, "0"] -> "权限"
      true -> "其他"
    end
  end

  # 兼容 JSON 字符串、数字和布尔值，避免状态字段来源不同导致显示错误。
  defp truthy_value?(value) when value in [true, 1, "1", "true", "TRUE"], do: true
  defp truthy_value?(_value), do: false

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
