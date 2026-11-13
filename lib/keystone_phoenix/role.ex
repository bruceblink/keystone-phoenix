defmodule KeystonePhoenix.Role do
  @moduledoc "Query boundary for role and role-menu permissions."

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Pagination
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Authz
  alias KeystonePhoenix.Authz.PolicyCache
  alias KeystonePhoenix.Menu.SysMenu
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}
  alias KeystonePhoenix.Role.Authorization
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
    case Params.parse_uuid(id) do
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
    ids = ids |> Enum.map(&parse_uuid/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      []
    else
      from(role in SysRole, where: role.deleted == false and role.role_id in ^ids)
      |> Repo.all()
    end
  end

  def list_roles_by_ids(_ids), do: []

  def create_role(attrs, options)

  def create_role(attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_write(options, "role:create", attrs) do
      do_create_role(attrs, Authorization.actor_id(options))
    end
  end

  def create_role(_attrs, _options), do: {:error, :authorization_required}

  defp do_create_role(attrs, actor_id) when is_map(attrs) do
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
    |> invalidate_policy_cache()
  end

  def update_role(id, attrs, options)

  def update_role(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_write(options, "role:update", attrs) do
      do_update_role(id, attrs, Authorization.actor_id(options))
    end
  end

  def update_role(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_update_role(id, attrs, actor_id) when is_map(attrs) do
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
      |> invalidate_policy_cache()
    end
  end

  def delete_role(id, options)

  def delete_role(id, options) when is_list(options) do
    with :ok <- Authorization.authorize_write(options, "role:delete") do
      do_delete_role(id, Authorization.actor_id(options))
    end
  end

  def delete_role(_id, _options), do: {:error, :authorization_required}

  defp do_delete_role(id, actor_id) do
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
          |> invalidate_policy_cache()
      end
    end
  end

  def change_status(id, status, options)

  def change_status(id, status, options) when is_list(options) do
    update_role(id, %{"status" => status, "menuIds" => menu_ids_for_role(id)}, options)
  end

  def change_status(_id, _status, _options), do: {:error, :authorization_required}

  def update_data_scope(id, attrs, options)

  def update_data_scope(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_write(options, "role:manage", attrs) do
      do_update_data_scope(id, attrs, Authorization.actor_id(options))
    end
  end

  def update_data_scope(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_update_data_scope(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, role} <- get_role(id) do
      attrs = normalize_attrs(attrs)

      role
      |> SysRole.changeset(attrs)
      |> Audit.put_actor(:updater_id, actor_id)
      |> Repo.update()
      |> invalidate_policy_cache()
    end
  end

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
    case parse_uuid(role_id) do
      nil -> %{total: 0, rows: []}
      role_id -> list_role_users(role_id, params, :allocated, actor)
    end
  end

  @doc "Lists active users that are not assigned to a role."
  def list_unallocated_users(role_id, params \\ %{}, actor \\ nil) do
    case parse_uuid(role_id) do
      nil -> %{total: 0, rows: []}
      role_id -> list_role_users(role_id, params, :unallocated, actor)
    end
  end

  @doc "Returns active user counts keyed by role ID in one database query."
  def user_counts(role_ids) when is_list(role_ids) do
    role_ids = Enum.filter(role_ids, &is_binary/1)

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
  def assign_users(role_id, user_ids, options)

  def assign_users(role_id, user_ids, options) when is_list(options) do
    with :ok <- Authorization.authorize_assignment(options, "role:assign"),
         {:ok, principal} <- Authorization.principal(options) do
      do_assign_users(role_id, user_ids, principal)
    end
  end

  def assign_users(_role_id, _user_ids, _options), do: {:error, :authorization_required}

  defp do_assign_users(role_id, user_ids, _actor) do
    with {:ok, role} <- get_role(role_id),
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
  def unassign_users(user_ids, options)

  def unassign_users(user_ids, options) when is_list(options) do
    with :ok <- Authorization.authorize_assignment(options, "role:assign"),
         {:ok, principal} <- Authorization.principal(options) do
      do_unassign_users(user_ids, principal)
    end
  end

  def unassign_users(_user_ids, _options), do: {:error, :authorization_required}

  defp do_unassign_users(user_ids, _actor) do
    with {:ok, user_ids} <- normalize_user_ids(user_ids) do
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

    query = Authz.scope_query(query, actor || %{})

    query =
      query
      |> filter_user_contains(:username, params["username"] || params[:username])
      |> filter_user_contains(:phone_number, params["phoneNumber"] || params[:phone_number])

    Pagination.page(query, params, :user_id, &User.user_maps/1)
  end

  defp normalize_user_ids(user_ids) when is_list(user_ids) do
    normalized = Enum.map(user_ids, &parse_uuid/1)

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
      Map.has_key?(attrs, "menuIds") -> normalize_menu_ids(Map.get(attrs, "menuIds"))
      Map.has_key?(attrs, :menu_ids) -> normalize_menu_ids(Map.get(attrs, :menu_ids))
      true -> nil
    end
  end

  defp normalize_ids(ids) when is_list(ids) do
    ids
    |> Enum.map(&parse_menu_id/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_ids(ids) when is_binary(ids) do
    ids
    |> String.split(",", trim: true)
    |> normalize_ids()
  end

  defp normalize_ids(_ids), do: []

  defp normalize_menu_ids(ids), do: normalize_ids(ids)

  defp parse_id_set(ids) when is_binary(ids) do
    ids
    |> String.split(",", trim: true)
    |> Enum.map(&parse_uuid/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp parse_id_set(ids) when is_list(ids),
    do: Enum.map(ids, &parse_uuid/1) |> Enum.reject(&is_nil/1)

  defp parse_id_set(_ids), do: []

  defp parse_uuid(value) do
    case Params.parse_uuid(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp parse_menu_id(value) when is_integer(value) and value > 0, do: value

  defp parse_menu_id(value) when is_binary(value) do
    case Params.parse_positive_integer(value) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp parse_menu_id(_value), do: nil

  defp invalidate_policy_cache({:ok, _value} = result) do
    PolicyCache.invalidate()
    result
  end

  defp invalidate_policy_cache(:ok = result) do
    PolicyCache.invalidate()
    result
  end

  defp invalidate_policy_cache(result), do: result

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
