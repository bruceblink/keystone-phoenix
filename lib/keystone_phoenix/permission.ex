defmodule KeystonePhoenix.Permission do
  @moduledoc "Menu permission and role data-scope checks for authenticated requests."

  import Ecto.Query

  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUser

  @doc "Checks whether a user has an exact menu permission."
  @spec allowed?(map(), String.t()) :: boolean()
  def allowed?(%{is_admin: true}, _permission), do: true
  def allowed?(%{"isAdmin" => 1}, _permission), do: true

  def allowed?(user, permission) when is_map(user) and is_binary(permission) do
    role_id = user_value(user, :role_id, "roleId")
    permission = String.trim(permission)

    if positive_integer?(role_id) and permission != "" do
      Repo.exists?(
        from menu in "sys_menu",
          join: role_menu in "sys_role_menu",
          on: role_menu.menu_id == menu.menu_id,
          join: role in "sys_role",
          on: role.role_id == role_menu.role_id,
          where:
            role_menu.role_id == ^role_id and role.deleted == false and role.status == 1 and
              menu.deleted == false and menu.status == 1 and menu.permission == ^permission
      )
    else
      false
    end
  rescue
    _error -> false
  end

  def allowed?(_user, _permission), do: false

  @doc "Returns a policy decision without collapsing storage failures into denial."
  @spec allowed_decision?(map(), String.t()) ::
          :allow | :deny | {:error, :authorization_unavailable}
  def allowed_decision?(%{is_admin: true}, _permission), do: :allow
  def allowed_decision?(%{"isAdmin" => 1}, _permission), do: :allow

  def allowed_decision?(user, permission) when is_map(user) and is_binary(permission) do
    role_id = user_value(user, :role_id, "roleId")
    permission = String.trim(permission)

    if positive_integer?(role_id) and permission != "" do
      if Repo.exists?(
           from menu in "sys_menu",
             join: role_menu in "sys_role_menu",
             on: role_menu.menu_id == menu.menu_id,
             join: role in "sys_role",
             on: role.role_id == role_menu.role_id,
             where:
               role_menu.role_id == ^role_id and role.deleted == false and role.status == 1 and
                 menu.deleted == false and menu.status == 1 and menu.permission == ^permission
         ),
         do: :allow,
         else: :deny
    else
      :deny
    end
  rescue
    _error -> {:error, :authorization_unavailable}
  end

  def allowed_decision?(_user, _permission), do: :deny

  @doc "Checks whether a delegated role write may change permission metadata."
  def role_metadata_allowed?(user, attrs) when is_map(attrs) do
    admin?(user) or
      not has_any_key?(attrs, [
        "menuIds",
        "dataScope",
        "deptIdSet",
        :menu_ids,
        :data_scope,
        :dept_id_set
      ]) or allowed?(user, "system:role:permission")
  end

  def role_metadata_allowed?(_user, _attrs), do: false

  @doc "Checks whether a delegated menu write may change permission metadata."
  def menu_metadata_allowed?(user, attrs) when is_map(attrs) do
    admin?(user) or
      not has_any_key?(attrs, ["permission", :permission]) or
      allowed?(user, "system:menu:permission")
  end

  def menu_metadata_allowed?(_user, _attrs), do: false

  defp has_any_key?(attrs, keys), do: Enum.any?(keys, &Map.has_key?(attrs, &1))

  @doc "Returns whether the authenticated user is an administrator."
  @spec admin?(map()) :: boolean()
  def admin?(%{is_admin: true}), do: true
  def admin?(%{"isAdmin" => 1}), do: true
  def admin?(_user), do: false

  @doc "Adds the current role's user data scope before counting or pagination."
  def scope_users(query, %{is_admin: true}), do: query
  def scope_users(query, %{"isAdmin" => 1}), do: query

  def scope_users(query, user) do
    role_id = user_value(user, :role_id, "roleId")

    with true <- positive_integer?(role_id),
         %SysRole{status: 1} = role <- Repo.get_by(SysRole, role_id: role_id, deleted: false) do
      scope_user_query(query, role, user)
    else
      _ -> where(query, false)
    end
  end

  @doc "Checks the existing user and a changed destination department at the write entrance."
  def user_update_allowed?(user, target_user_id, attrs) do
    with target_id when is_integer(target_id) <- parse_positive_integer(target_user_id) do
      case Repo.get_by(SysUser, user_id: target_id, deleted: false) do
        nil ->
          true

        target ->
          check_scope(user, target.dept_id, target.user_id) and
            destination_allowed?(user, target, attrs)
      end
    else
      _ -> false
    end
  end

  @doc "Checks a department or user target against the user's role data scope."
  @spec data_scope_allowed?(map(), :dept | :user, term()) :: boolean()
  def data_scope_allowed?(user, :dept, target_dept_id) do
    check_scope(user, parse_positive_integer(target_dept_id), nil)
  end

  def data_scope_allowed?(user, :user, target_user_id) do
    target_user_id = parse_positive_integer(target_user_id)

    case target_user_id do
      nil ->
        false

      user_id ->
        case Repo.get_by(SysUser, user_id: user_id, deleted: false) do
          nil -> true
          target -> check_scope(user, target.dept_id, target.user_id)
        end
    end
  rescue
    _error -> false
  end

  @doc "Checks every user ID in a bulk operation against the current data scope."
  @spec data_scope_users_allowed?(map(), term()) :: boolean()
  def data_scope_users_allowed?(user, ids) when is_binary(ids) do
    data_scope_users_allowed?(user, String.split(ids, ",", trim: true))
  end

  def data_scope_users_allowed?(user, ids) when is_list(ids) do
    ids != [] and Enum.all?(ids, &data_scope_allowed?(user, :user, &1))
  end

  def data_scope_users_allowed?(_user, _ids), do: false

  @doc "Checks whether an actor may assign the requested role during an import."
  @spec role_assignment_allowed?(map(), term()) :: boolean()
  def role_assignment_allowed?(actor, role_id) do
    cond do
      admin?(actor) -> true
      is_nil(parse_positive_integer(role_id)) -> true
      true -> false
    end
  end

  defp destination_allowed?(user, target, attrs) do
    if Map.has_key?(attrs, "deptId") or Map.has_key?(attrs, :dept_id) do
      destination = parse_positive_integer(Map.get(attrs, "deptId", attrs[:dept_id]))
      destination == target.dept_id or check_scope(user, destination, nil)
    else
      true
    end
  end

  defp scope_user_query(query, %{data_scope: 1}, _user), do: query

  defp scope_user_query(query, %{data_scope: 2, dept_id_set: ids}, _user) do
    dept_ids = parse_id_set(ids)
    where(query, [target], target.dept_id in ^dept_ids)
  end

  defp scope_user_query(query, %{data_scope: 3}, user) do
    case user_value(user, :dept_id, "deptId") do
      nil -> where(query, false)
      dept_id -> where(query, [target], target.dept_id == ^dept_id)
    end
  end

  defp scope_user_query(query, %{data_scope: 4}, user) do
    case user_value(user, :dept_id, "deptId") do
      nil ->
        where(query, false)

      dept_id ->
        ancestor = Integer.to_string(dept_id)

        departments =
          from dept in SysDept,
            where:
              dept.deleted == false and
                (dept.dept_id == ^dept_id or
                   fragment("? = ANY(string_to_array(?, ','))", ^ancestor, dept.ancestors)),
            select: dept.dept_id

        where(query, [target], target.dept_id in subquery(departments))
    end
  end

  defp scope_user_query(query, %{data_scope: 5}, user) do
    user_id = user_value(user, :user_id, "userId")
    where(query, [target], target.user_id == ^user_id)
  end

  defp scope_user_query(query, _role, _user), do: where(query, false)

  defp check_scope(%{is_admin: true}, _target_dept_id, _target_user_id), do: true

  defp check_scope(%{"isAdmin" => 1}, _target_dept_id, _target_user_id), do: true

  defp check_scope(user, target_dept_id, target_user_id) do
    role_id = user_value(user, :role_id, "roleId")

    with true <- positive_integer?(role_id),
         %SysRole{} = role <- Repo.get_by(SysRole, role_id: role_id, deleted: false),
         true <- role.status == 1 do
      scope_matches?(role, user, target_dept_id, target_user_id)
    else
      _ -> false
    end
  rescue
    _error -> false
  end

  defp scope_matches?(%{data_scope: 1}, _user, _target_dept_id, _target_user_id), do: true

  defp scope_matches?(
         %{data_scope: 2, dept_id_set: dept_id_set},
         _user,
         target_dept_id,
         _target_user_id
       ) do
    target_dept_id != nil and target_dept_id in parse_id_set(dept_id_set)
  end

  defp scope_matches?(%{data_scope: 3}, user, target_dept_id, _target_user_id) do
    user_value(user, :dept_id, "deptId") == target_dept_id and target_dept_id != nil
  end

  defp scope_matches?(%{data_scope: 4}, user, target_dept_id, _target_user_id) do
    current_dept_id = user_value(user, :dept_id, "deptId")

    with current when is_integer(current) <- parse_positive_integer(current_dept_id),
         target when is_integer(target) <- target_dept_id,
         %SysDept{ancestors: ancestors} <- Repo.get_by(SysDept, dept_id: target, deleted: false) do
      current == target or Integer.to_string(current) in String.split(ancestors || "", ",")
    else
      _ -> false
    end
  end

  defp scope_matches?(%{data_scope: 5}, user, _target_dept_id, target_user_id) do
    user_value(user, :user_id, "userId") == target_user_id and target_user_id != nil
  end

  defp scope_matches?(_role, _user, _target_dept_id, _target_user_id), do: false

  defp parse_id_set(value) when is_binary(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&parse_positive_integer/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_id_set(_value), do: []

  defp user_value(user, atom_key, string_key) do
    Map.get(user, atom_key, Map.get(user, string_key))
  end

  defp positive_integer?(value), do: not is_nil(parse_positive_integer(value))

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} when integer > 0 -> integer
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil
end
