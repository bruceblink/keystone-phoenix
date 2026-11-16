defmodule KeystonePhoenix.User.RoleMembership do
  @moduledoc "用户和角色关联表的只读查询边界；阶段 A 不执行鉴权或写入切换。"

  import Ecto.Query

  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser
  alias KeystonePhoenix.User.SysUserRole

  @doc "把用户的角色关联替换为指定集合，并保留旧 role_id 兼容字段。"
  def replace_user_roles(user_ids, role_ids) when is_list(user_ids) and is_list(role_ids) do
    Repo.delete_all(from(membership in SysUserRole, where: membership.user_id in ^user_ids))

    if role_ids != [] and user_ids != [] do
      Repo.insert_all(
        SysUserRole,
        for(user_id <- user_ids, role_id <- role_ids, do: %{user_id: user_id, role_id: role_id}),
        on_conflict: :nothing
      )
    end

    :ok
  end

  def replace_user_roles(user_ids, role_id) when is_list(user_ids),
    do: replace_user_roles(user_ids, List.wrap(role_id))

  @doc "根据 Native roleCodes 解析启用角色；未知或停用角色整体失败。"
  def resolve_role_codes(codes) when is_list(codes) do
    codes =
      codes |> Enum.map(&String.trim(to_string(&1))) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    roles =
      from(role in SysRole,
        where: role.role_key in ^codes and role.deleted == false and role.status == 1
      )
      |> Repo.all()

    role_map = Map.new(roles, &{&1.role_key, &1.role_id})

    if map_size(role_map) == length(codes),
      do: {:ok, Enum.map(codes, &Map.fetch!(role_map, &1))},
      else: {:error, :role_codes_unsupported}
  end

  def resolve_role_codes(_codes), do: {:error, :role_codes_unsupported}

  @doc "在同一事务中创建用户并写入全部角色关联。"
  def insert_user(changeset, role_ids) do
    Repo.transaction(fn ->
      case Repo.insert(changeset) do
        {:ok, user} ->
          replace_user_roles([user.user_id], role_ids)
          user

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def insert_user(changeset),
    do: insert_user(changeset, List.wrap(Ecto.Changeset.get_field(changeset, :role_id)))

  @doc "在同一事务中更新用户并同步角色关联。"
  def update_user(changeset, role_ids \\ :preserve) do
    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, user} ->
          if role_ids != :preserve,
            do: replace_user_roles([user.user_id], role_ids)

          user

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "为用户追加目标角色，并把目标角色作为旧字段的首选角色。"
  def assign_user_roles(user_ids, role_id) when is_list(user_ids) do
    query = from(user in SysUser, where: user.deleted == false and user.user_id in ^user_ids)
    affected_ids = Repo.all(from(user in query, select: user.user_id))

    if length(affected_ids) != length(Enum.uniq(user_ids)),
      do: Repo.rollback(:not_found)

    Repo.insert_all(SysUserRole, Enum.map(affected_ids, &%{user_id: &1, role_id: role_id}),
      on_conflict: :nothing
    )

    Repo.update_all(
      query,
      set: [role_id: role_id, update_time: DateTime.utc_now()],
      inc: [permission_version: 1]
    )
  end

  @doc "只移除目标角色关联，并选择剩余角色作为兼容字段。"
  def unassign_user_roles(user_ids, role_id) when is_list(user_ids) do
    query = from(user in SysUser, where: user.deleted == false and user.user_id in ^user_ids)
    affected_ids = Repo.all(from(user in query, select: user.user_id))

    if length(affected_ids) != length(Enum.uniq(user_ids)),
      do: Repo.rollback(:not_found)

    Repo.delete_all(
      from(membership in SysUserRole,
        where: membership.user_id in ^user_ids and membership.role_id == ^role_id
      )
    )

    Enum.each(affected_ids, fn user_id ->
      preferred_role =
        from(membership in SysUserRole,
          where: membership.user_id == ^user_id,
          order_by: membership.role_id,
          select: membership.role_id,
          limit: 1
        )
        |> Repo.one()

      Repo.update_all(
        from(user in SysUser, where: user.user_id == ^user_id),
        set: [role_id: preferred_role, update_time: DateTime.utc_now()],
        inc: [permission_version: 1]
      )
    end)

    :ok
  end

  @doc "兼容旧接口：清除用户的全部角色关联，并清空 role_id。"
  def unassign_all_user_roles(user_ids) when is_list(user_ids) do
    query = from(user in SysUser, where: user.deleted == false and user.user_id in ^user_ids)
    affected_ids = Repo.all(from(user in query, select: user.user_id))

    if length(affected_ids) != length(Enum.uniq(user_ids)),
      do: Repo.rollback(:not_found)

    Repo.delete_all(from(membership in SysUserRole, where: membership.user_id in ^user_ids))

    Repo.update_all(query,
      set: [role_id: nil, update_time: DateTime.utc_now()],
      inc: [permission_version: 1]
    )

    :ok
  end

  @doc "在同一事务中更新兼容角色字段并镜像当前角色集合。"
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
