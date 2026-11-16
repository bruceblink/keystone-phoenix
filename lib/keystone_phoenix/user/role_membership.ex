defmodule KeystonePhoenix.User.RoleMembership do
  @moduledoc "用户和角色关联表的只读查询边界；阶段 A 不执行鉴权或写入切换。"

  import Ecto.Query

  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUserRole

  @doc "读取用户当前已保存的规范角色 ID，并按 ID 排序。"
  def list_role_ids_for_user(user_id) do
    case Params.parse_uuid(user_id) do
      {:ok, user_id} ->
        from(membership in SysUserRole,
          where: membership.user_id == ^user_id,
          order_by: membership.role_id,
          select: membership.role_id
        )
        |> Repo.all()

      :error ->
        []
    end
  end

  @doc "读取角色当前已保存的规范用户 ID，并按 ID 排序。"
  def list_user_ids_for_role(role_id) do
    case Params.parse_uuid(role_id) do
      {:ok, role_id} ->
        from(membership in SysUserRole,
          where: membership.role_id == ^role_id,
          order_by: membership.user_id,
          select: membership.user_id
        )
        |> Repo.all()

      :error ->
        []
    end
  end
end
