defmodule KeystonePhoenix.Role.UserCount do
  @moduledoc "按主角色字段和多角色关联统计未删除用户。"

  import Ecto.Query

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  @doc "统计指定角色关联的未删除用户，并避免同一用户重复计数。"
  def count(role_id) do
    member_ids =
      from(membership in SysUserRole,
        where: membership.role_id == ^role_id,
        select: membership.user_id
      )

    from(user in SysUser,
      where:
        user.deleted == false and
          (user.role_id == ^role_id or user.user_id in subquery(member_ids))
    )
    |> Repo.aggregate(:count, :user_id)
  end
end
