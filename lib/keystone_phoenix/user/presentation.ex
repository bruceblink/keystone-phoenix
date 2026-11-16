defmodule KeystonePhoenix.User.Presentation do
  @moduledoc "用户 DTO 映射和关联名称加载。"

  alias KeystonePhoenix.Department
  alias KeystonePhoenix.Post
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.RoleMembership

  @empty_relation_names %{
    departments: %{},
    posts: %{},
    roles: %{},
    role_keys: %{},
    role_codes: %{},
    users: %{}
  }

  @doc "批量加载用户关联名称，并返回前端用户字段。"
  def user_maps(users) when is_list(users) do
    names = relation_names(users)
    Enum.map(users, &user_to_map(&1, names))
  end

  @doc "加载单个用户的关联名称。"
  def user_to_map_with_relations(user),
    do: user |> List.wrap() |> user_maps() |> List.first() || user_to_map(user)

  @doc "映射单个用户的稳定字段。"
  def user_to_map(user), do: user_to_map(user, @empty_relation_names)

  defp user_to_map(user, names) do
    role_codes =
      case Map.get(names.role_codes, user.user_id) do
        codes when is_list(codes) and codes != [] -> codes
        _ -> fallback_role_codes(names, user)
      end

    %{
      "userId" => user.user_id,
      "postId" => user.post_id,
      "roleId" => user.role_id,
      "deptId" => user.dept_id,
      "username" => user.username,
      "nickname" => user.nickname,
      "userType" => user.user_type,
      "email" => user.email,
      "phoneNumber" => user.phone_number,
      "sex" => user.sex,
      "avatar" => user.avatar,
      "mustChangePassword" => user.must_change_password,
      "status" => user.status,
      "loginIp" => user.login_ip,
      "loginDate" => format_datetime(user.login_date),
      "deptName" => Map.get(names.departments, user.dept_id, ""),
      "postName" => Map.get(names.posts, user.post_id, ""),
      "roleName" => Map.get(names.roles, user.role_id, ""),
      "roleKey" => Map.get(names.role_keys, user.role_id, ""),
      "roles" => role_codes,
      "roleCodes" => role_codes,
      "creatorName" => Map.get(names.users, user.creator_id, ""),
      "updaterName" => Map.get(names.users, user.updater_id, ""),
      "creatorId" => user.creator_id,
      "createTime" => format_datetime(user.create_time),
      "updaterId" => user.updater_id,
      "updateTime" => format_datetime(user.update_time),
      "remark" => user.remark
    }
  end

  defp relation_names(users) do
    role_ids = all_role_ids(users)

    %{
      departments:
        users
        |> relation_ids(:dept_id)
        |> Department.list_depts_by_ids()
        |> names_by_id(:dept_id, :dept_name),
      posts:
        users
        |> relation_ids(:post_id)
        |> Post.list_posts_by_ids()
        |> names_by_id(:post_id, :post_name),
      roles: role_ids |> Role.list_roles_by_ids() |> names_by_id(:role_id, :role_name),
      role_keys: role_ids |> Role.list_roles_by_ids() |> names_by_id(:role_id, :role_key),
      role_codes:
        Map.new(users, fn user ->
          codes =
            user.user_id
            |> RoleMembership.list_role_ids_for_user()
            |> Role.list_roles_by_ids()
            |> Enum.map(& &1.role_key)

          {user.user_id, codes}
        end),
      users:
        (relation_ids(users, :creator_id) ++ relation_ids(users, :updater_id))
        |> Enum.uniq()
        |> User.list_users_by_ids()
        |> names_by_id(:user_id, :username)
    }
  end

  defp relation_ids(users, field),
    do: users |> Enum.map(&Map.get(&1, field)) |> Enum.filter(&is_binary/1) |> Enum.uniq()

  # 角色关联表是多角色字段的来源，旧 role_id 只负责兼容首选角色。
  defp all_role_ids(users) do
    (relation_ids(users, :role_id) ++
       Enum.flat_map(users, &RoleMembership.list_role_ids_for_user(&1.user_id)))
    |> Enum.uniq()
  end

  defp fallback_role_codes(names, user),
    do: List.wrap(Map.get(names.role_keys, user.role_id, "")) |> Enum.reject(&(&1 == ""))

  defp names_by_id(records, id_field, name_field),
    do: Map.new(records, &{Map.get(&1, id_field), Map.get(&1, name_field)})

  defp format_datetime(nil), do: nil
  defp format_datetime(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
