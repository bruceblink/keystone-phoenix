defmodule KeystonePhoenix.Auth.LoginAuthorization do
  @moduledoc "计算登录角色与权限，并提供 LiveView 校验所需的最小身份字段。"

  alias KeystonePhoenix.Menu
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.RoleMembership

  @base_user_fields ~w(
    userId postId roleId deptId username nickname userType email phoneNumber sex avatar
    mustChangePassword status loginIp loginDate creatorId createTime updaterId updateTime remark
  )

  @doc "返回首选角色、当前角色编码和最新权限列表。"
  def role_permissions(user) do
    role_ids = role_ids(user)
    role_key_map = role_key_map(role_ids)
    role_keys = role_keys(role_ids, role_key_map)
    preferred_role_key = preferred_role_key(user, role_ids, role_key_map, role_keys)

    {preferred_role_key, role_keys, Menu.permissions_for_user(user)}
  end

  @doc "返回会话校验用身份字段，不读取岗位、部门和操作人名称。"
  def current_login_authorization(user) do
    {_role_key, roles, permissions} = role_permissions(user)

    # 复用不访问数据库的用户字段映射，只刷新基础字段并更新最新角色编码。
    user_info =
      user
      |> User.user_to_map()
      |> Map.take(@base_user_fields)
      |> Map.merge(%{"roles" => roles, "roleCodes" => roles})

    %{
      "userInfo" => user_info,
      "permissions" => permissions
    }
  end

  # 兼容期间优先使用关联表；关联表没有记录时回退旧 role_id 字段。
  defp role_ids(user) do
    case RoleMembership.list_role_ids_for_user(user.user_id) do
      [] -> List.wrap(user.role_id)
      ids -> ids
    end
  end

  defp role_keys(role_ids, role_map) do
    role_ids
    |> Enum.map(&Map.get(role_map, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp preferred_role_key(user, role_ids, role_map, role_keys) do
    preferred_id = if user.role_id in role_ids, do: user.role_id, else: List.first(role_ids)
    Map.get(role_map, preferred_id, List.first(role_keys) || "")
  end

  defp role_key_map(role_ids),
    do: role_ids |> Role.list_roles_by_ids() |> Map.new(&{&1.role_id, &1.role_key})
end
