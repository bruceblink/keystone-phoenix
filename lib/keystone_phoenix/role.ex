defmodule KeystonePhoenix.Role do
  @moduledoc "Query boundary for role and role-menu permissions."

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Pagination
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Permission
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.User
  alias KeystonePhoenix.User.SysUser

  @role_attrs [
    {"roleName", :role_name},
    {"roleKey", :role_key},
    {"roleSort", :role_sort},
    {"dataScope", :data_scope},
    {"deptIdSet", :dept_id_set},
    {"status", :status},
    {"remark", :remark}
  ]

  def list_roles(params \\ %{}) do
    query =
      from(r in SysRole,
        where: r.deleted == false,
        order_by: [asc: r.role_sort, asc: r.role_id]
      )

    query = filter_contains(query, :role_name, params["roleName"] || params[:role_name])
    query = filter_contains(query, :role_key, params["roleKey"] || params[:role_key])
    query = filter_status(query, params["status"] || params[:status])
    Pagination.page(query, params, :role_id, &role_to_map/1)
  end

  def get_role(id) do
    case Params.parse_positive_integer(id) do
      {:ok, id} ->
        case Repo.get_by(SysRole, role_id: id, deleted: false) do
          nil -> {:error, :not_found}
          role -> {:ok, role}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc "Returns active roles keyed by ID with one database query."
  def list_roles_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.map(&parse_positive_integer/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      []
    else
      from(role in SysRole, where: role.deleted == false and role.role_id in ^ids)
      |> Repo.all()
    end
  end

  def list_roles_by_ids(_ids), do: []

  def create_role(attrs, actor_id \\ nil)

  def create_role(attrs, actor_id) when is_map(attrs) do
    menu_ids = menu_ids_from(attrs) || []
    attrs = normalize_attrs(attrs)

    Repo.transaction(fn ->
      changeset = SysRole.changeset(%SysRole{}, attrs) |> Audit.put_actor(:creator_id, actor_id)

      role =
        case Repo.insert(changeset) do
          {:ok, role} -> role
          {:error, changeset} -> Repo.rollback(changeset)
        end

      replace_menu_ids(role.role_id, menu_ids)
      role
    end)
  end

  def create_role(_attrs, _actor_id), do: {:error, invalid_changeset(:role_name)}

  def update_role(id, attrs, actor_id \\ nil)

  def update_role(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, role} <- get_role(id) do
      menu_ids = menu_ids_from(attrs)
      attrs = normalize_attrs(attrs)

      Repo.transaction(fn ->
        changeset = SysRole.changeset(role, attrs) |> Audit.put_actor(:updater_id, actor_id)

        updated =
          case Repo.update(changeset) do
            {:ok, updated} -> updated
            {:error, changeset} -> Repo.rollback(changeset)
          end

        if is_list(menu_ids), do: replace_menu_ids(updated.role_id, menu_ids)
        updated
      end)
    end
  end

  def update_role(_id, _attrs, _actor_id), do: {:error, invalid_changeset(:role_name)}

  def delete_role(id, actor_id \\ nil) do
    with {:ok, role} <- get_role(id) do
      cond do
        role.role_key == "admin" ->
          {:error, :protected_role}

        user_count(role.role_id) > 0 ->
          {:error, :has_users}

        true ->
          Repo.transaction(fn ->
            Repo.delete_all(from(rm in SysRoleMenu, where: rm.role_id == ^role.role_id))

            changeset = Ecto.Changeset.change(role, deleted: true)
            changeset = Audit.put_actor(changeset, :updater_id, actor_id)

            case Repo.update(changeset) do
              {:ok, _deleted} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)
      end
    end
  end

  def change_status(id, status, actor_id \\ nil) do
    update_role(id, %{"status" => status, "menuIds" => menu_ids_for_role(id)}, actor_id)
  end

  def update_data_scope(id, attrs, actor_id \\ nil)

  def update_data_scope(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, role} <- get_role(id) do
      attrs = normalize_attrs(attrs)

      role
      |> SysRole.changeset(attrs)
      |> Audit.put_actor(:updater_id, actor_id)
      |> Repo.update()
    end
  end

  def update_data_scope(_id, _attrs, _actor_id), do: {:error, invalid_changeset(:data_scope)}

  def menu_ids_for_role(role_id) do
    from(rm in SysRoleMenu,
      join: menu in SysMenu,
      on: menu.menu_id == rm.menu_id,
      where: rm.role_id == ^role_id and menu.deleted == false,
      select: rm.menu_id
    )
    |> Repo.all()
  end

  @doc "Returns the department IDs selected for a role data scope."
  def dept_ids_for_role(%SysRole{dept_id_set: dept_id_set}), do: parse_id_set(dept_id_set)

  @doc "Lists users currently assigned to a role."
  def list_allocated_users(role_id, params \\ %{}, actor \\ nil) do
    case parse_positive_integer(role_id) do
      nil -> %{total: 0, rows: []}
      role_id -> list_role_users(role_id, params, :allocated, actor)
    end
  end

  @doc "Lists active users that are not assigned to a role."
  def list_unallocated_users(role_id, params \\ %{}, actor \\ nil) do
    case parse_positive_integer(role_id) do
      nil -> %{total: 0, rows: []}
      role_id -> list_role_users(role_id, params, :unallocated, actor)
    end
  end

  @doc "Returns active user counts keyed by role ID in one database query."
  def user_counts(role_ids) when is_list(role_ids) do
    role_ids = Enum.filter(role_ids, &(is_integer(&1) and &1 > 0))

    if role_ids == [] do
      %{}
    else
      from(u in SysUser,
        where: u.deleted == false and u.role_id in ^role_ids,
        group_by: u.role_id,
        select: {u.role_id, count(u.user_id)}
      )
      |> Repo.all()
      |> Map.new()
    end
  end

  def user_counts(_role_ids), do: %{}

  @doc "Assigns a batch of users to an enabled role."
  def assign_users(role_id, user_ids, actor \\ nil) do
    with :ok <- assignment_allowed?(actor),
         {:ok, role} <- get_role(role_id),
         true <- role.status == 1,
         {:ok, user_ids} <- normalize_user_ids(user_ids) do
      update_user_assignments(user_ids, role.role_id)
    else
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, :not_found} -> {:error, :not_found}
      {:error, :invalid_ids} -> {:error, :invalid_ids}
      false -> {:error, :role_unavailable}
    end
  end

  @doc "Removes role assignments from a batch of users."
  def unassign_users(user_ids, actor \\ nil) do
    with :ok <- assignment_allowed?(actor),
         {:ok, user_ids} <- normalize_user_ids(user_ids) do
      update_user_assignments(user_ids, nil)
    end
  end

  defp replace_menu_ids(role_id, menu_ids) do
    case validate_menu_ids(menu_ids) do
      :ok ->
        Repo.delete_all(from(rm in SysRoleMenu, where: rm.role_id == ^role_id))

        if menu_ids != [] do
          Repo.insert_all("sys_role_menu", Enum.map(menu_ids, &%{role_id: role_id, menu_id: &1}))
        end

        :ok

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp validate_menu_ids([]), do: :ok

  defp validate_menu_ids(menu_ids) do
    count =
      from(menu in SysMenu,
        where: menu.menu_id in ^menu_ids and menu.deleted == false,
        select: count(menu.menu_id)
      )
      |> Repo.one()

    if count == length(menu_ids), do: :ok, else: {:error, :menu_not_found}
  end

  defp update_user_assignments(user_ids, role_id) do
    result =
      Repo.transaction(fn ->
        Repo.update_all(
          from(u in SysUser, where: u.deleted == false and u.user_id in ^user_ids),
          set: [role_id: role_id, update_time: DateTime.utc_now()]
        )
        |> update_result(user_ids)
      end)

    case result do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_result({count, _}, ids) when count == length(ids), do: :ok
  defp update_result(_result, _ids), do: Repo.rollback(:not_found)

  defp list_role_users(role_id, params, mode, actor) do
    query =
      from u in SysUser,
        where: u.deleted == false,
        order_by: [desc: u.user_id]

    query =
      case mode do
        :allocated -> where(query, [user], user.role_id == ^role_id)
        :unallocated -> where(query, [user], is_nil(user.role_id) or user.role_id != ^role_id)
      end

    query = Permission.scope_users(query, actor || %{is_admin: true})

    query =
      query
      |> filter_user_contains(:username, params["username"] || params[:username])
      |> filter_user_contains(:phone_number, params["phoneNumber"] || params[:phone_number])

    Pagination.page(query, params, :user_id, &User.user_maps/1)
  end

  defp assignment_allowed?(nil), do: :ok

  defp assignment_allowed?(actor),
    do: if(Permission.admin?(actor), do: :ok, else: {:error, :forbidden})

  defp normalize_user_ids(user_ids) when is_list(user_ids) do
    normalized = Enum.map(user_ids, &parse_positive_integer/1)

    if normalized == [] or Enum.any?(normalized, &is_nil/1),
      do: {:error, :invalid_ids},
      else: {:ok, Enum.uniq(normalized)}
  end

  defp normalize_user_ids(user_ids) when is_binary(user_ids) do
    user_ids |> String.split(",", trim: true) |> normalize_user_ids()
  end

  defp normalize_user_ids(_user_ids), do: {:error, :invalid_ids}

  defp filter_user_contains(query, _field, nil), do: query
  defp filter_user_contains(query, _field, ""), do: query

  defp filter_user_contains(query, field, value) do
    pattern = "%" <> String.trim(to_string(value)) <> "%"
    where(query, [user], ilike(field(user, ^field), ^pattern))
  end

  defp user_count(role_id) do
    from(u in SysUser, where: u.role_id == ^role_id and u.deleted == false)
    |> Repo.aggregate(:count, :user_id)
  end

  def role_to_map(role) do
    %{
      "roleId" => role.role_id,
      "roleName" => role.role_name,
      "roleKey" => role.role_key,
      "roleSort" => role.role_sort,
      "dataScope" => role.data_scope,
      "deptIdSet" => role.dept_id_set,
      "status" => role.status,
      "remark" => role.remark,
      "createTime" => format_datetime(role.create_time)
    }
  end

  defp normalize_attrs(attrs) do
    Enum.reduce(@role_attrs, %{}, fn {json_key, atom_key}, normalized ->
      cond do
        Map.has_key?(attrs, json_key) -> Map.put(normalized, atom_key, Map.get(attrs, json_key))
        Map.has_key?(attrs, atom_key) -> Map.put(normalized, atom_key, Map.get(attrs, atom_key))
        true -> normalized
      end
    end)
  end

  defp menu_ids_from(attrs) do
    cond do
      Map.has_key?(attrs, "menuIds") -> normalize_ids(Map.get(attrs, "menuIds"))
      Map.has_key?(attrs, :menu_ids) -> normalize_ids(Map.get(attrs, :menu_ids))
      true -> nil
    end
  end

  defp normalize_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&parse_positive_integer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_ids(ids) when is_binary(ids) do
    ids
    |> String.split(",", trim: true)
    |> normalize_ids()
  end

  defp normalize_ids(_ids), do: []

  defp parse_id_set(ids) when is_binary(ids) do
    ids
    |> String.split(",", trim: true)
    |> Enum.map(&parse_positive_integer/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_id_set(ids) when is_list(ids), do: normalize_ids(ids)
  defp parse_id_set(_ids), do: []

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {number, ""} when number > 0 -> number
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp invalid_changeset(field),
    do: Ecto.Changeset.add_error(Ecto.Changeset.change(%SysRole{}), field, "参数无效")

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    pattern = "%" <> String.trim(to_string(value)) <> "%"
    where(query, [role], ilike(field(role, ^field), ^pattern))
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, ""), do: query

  defp filter_status(query, value) do
    case Integer.parse(to_string(value)) do
      {status, ""} -> where(query, [role], role.status == ^status)
      _ -> query
    end
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
