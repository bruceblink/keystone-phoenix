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
