defmodule KeystonePhoenix.Role.PermissionVersion do
  @moduledoc "角色变更后的用户权限版本更新。"

  import Ecto.Query

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  @doc "递增所有直接或间接关联目标角色的用户权限版本。"
  def bump_for_role(role_id) do
    user_ids =
      from(u in SysUser,
        left_join: membership in SysUserRole,
        on: membership.user_id == u.user_id and membership.role_id == ^role_id,
        where: u.deleted == false and (u.role_id == ^role_id or not is_nil(membership.user_id)),
        select: u.user_id
      )
      |> Repo.all()

    if user_ids != [] do
      Repo.update_all(
        from(u in SysUser, where: u.user_id in ^user_ids),
        inc: [permission_version: 1]
      )
    end

    :ok
  end
end
