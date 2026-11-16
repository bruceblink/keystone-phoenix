defmodule KeystonePhoenix.User.RoleMembership do
  @moduledoc "用户和角色关联表的只读查询边界；阶段 A 不执行鉴权或写入切换。"

  import Ecto.Query

  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  @doc "在当前单角色兼容模式下替换用户的全部角色关联。"
  def replace_user_roles(user_ids, role_id) when is_list(user_ids) do
    Repo.delete_all(from(membership in SysUserRole, where: membership.user_id in ^user_ids))

    if is_binary(role_id) and user_ids != [] do
      Repo.insert_all(
        SysUserRole,
        Enum.map(user_ids, &%{user_id: &1, role_id: role_id}),
        on_conflict: :nothing
      )
    end

    :ok
  end

  @doc "在同一事务中创建用户并镜像当前单角色关联。"
  def insert_user(changeset) do
    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, user} ->
          replace_user_roles([user.user_id], user.role_id)
          user

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "在同一事务中更新用户并同步角色关联。"
  def update_user(changeset) do
    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, user} ->
          if Map.has_key?(changeset.changes, :role_id),
            do: replace_user_roles([user.user_id], user.role_id)

          user

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "在同一事务中更新兼容角色字段并镜像关联表。"
  def update_user_roles(user_ids, role_id, expected_role_id \\ :any) when is_list(user_ids) do
    query = from(user in SysUser, where: user.deleted == false and user.user_id in ^user_ids)

    query =
      if expected_role_id == :any,
        do: query,
        else: where(query, [user], user.role_id == ^expected_role_id)

    affected_ids = Repo.all(from(user in query, select: user.user_id))

    result =
      Repo.update_all(
        query,
        set: [role_id: role_id, update_time: DateTime.utc_now()],
        inc: [permission_version: 1]
      )

    replace_user_roles(affected_ids, role_id)
    result
  end

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
