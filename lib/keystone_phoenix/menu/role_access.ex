defmodule KeystonePhoenix.Menu.RoleAccess do
  @moduledoc "读取用户全部启用角色的菜单和权限并集。"

  import Ecto.Query

  alias KeystonePhoenix.Authz.SysPermission
  alias KeystonePhoenix.Authz.SysRolePermission
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.Role.SysRoleMenu
  alias KeystonePhoenix.User.RoleMembership

  @doc "返回当前用户可见的启用菜单记录，并按菜单顺序去重。"
  def menu_rows(user) do
    role_ids = active_role_ids(user)

    if role_ids == [] do
      []
    else
      from(menu in KeystonePhoenix.Menu.SysMenu,
        join: role_menu in SysRoleMenu,
        on: role_menu.menu_id == menu.menu_id,
        where: menu.deleted == false and menu.status == 1 and role_menu.role_id in ^role_ids,
        order_by: [asc: menu.parent_id, asc: menu.menu_sort, asc: menu.menu_id],
        distinct: true
      )
      |> Repo.all()
    end
  end

  @doc "返回当前用户全部启用角色的按钮和路由权限并集。"
  def permissions(user) do
    role_ids = active_role_ids(user)

    if role_ids == [] do
      []
    else
      from(role_permission in SysRolePermission,
        join: permission in SysPermission,
        on: permission.permission_id == role_permission.permission_id,
        where:
          role_permission.role_id in ^role_ids and permission.status == 1 and
            permission.deprecated == false,
        select: permission.permission,
        distinct: true,
        order_by: permission.permission
      )
      |> Repo.all()
    end
  end

  # 迁移期间无关联记录的旧主体继续使用 role_id 或 roles 字段。
  defp active_role_ids(user) do
    user
    |> role_ids()
    |> active_role_ids_from_storage()
  end

  defp active_role_ids_from_storage([]), do: []

  defp active_role_ids_from_storage(role_ids) do
    from(role in SysRole,
      where: role.role_id in ^role_ids and role.deleted == false and role.status == 1,
      select: role.role_id
    )
    |> Repo.all()
  end

  defp role_ids(user) when is_map(user) do
    persisted =
      case Map.get(user, :user_id, Map.get(user, "userId")) do
        user_id when is_binary(user_id) -> RoleMembership.list_role_ids_for_user(user_id)
        _ -> []
      end

    if persisted == [], do: legacy_role_ids(user), else: persisted
  rescue
    _error -> legacy_role_ids(user)
  end

  defp role_ids(_user), do: []

  defp legacy_role_ids(user) do
    case Map.get(user, :role_id, Map.get(user, "roleId")) do
      nil -> List.wrap(Map.get(user, :roles, Map.get(user, "roles")))
      role_id -> [role_id]
    end
    |> Enum.map(&parse_uuid/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_uuid(value) do
    case KeystonePhoenix.Params.parse_uuid(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end
end
