defmodule KeystonePhoenix.Department do
  @moduledoc "Query boundary for department management."

  import Ecto.Query

  alias KeystonePhoenix.Audit
  alias KeystonePhoenix.Department.Authorization
  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Tree
  alias KeystonePhoenix.User.SysUser

  @dept_attrs [
    {"parentId", :parent_id},
    {"ancestors", :ancestors},
    {"deptName", :dept_name},
    {"orderNum", :order_num},
    {"leaderId", :leader_id},
    {"leaderName", :leader_name},
    {"phone", :phone},
    {"email", :email},
    {"status", :status}
  ]

  def list_depts(params \\ %{}) do
    from(d in SysDept,
      where: d.deleted == false,
      order_by: [asc: d.parent_id, asc: d.order_num, asc: d.dept_id]
    )
    |> filter_status(params["status"] || params[:status])
    |> Repo.all()
    |> Enum.map(&dept_to_map/1)
  end

  def list_dropdown do
    Tree.nest(list_depts(), "parentId", "deptId")
  end

  def get_dept(id) do
    case Params.parse_positive_integer(id) do
      {:ok, id} ->
        case Repo.get_by(SysDept, dept_id: id, deleted: false) do
          nil -> {:error, :not_found}
          dept -> {:ok, dept}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc "Returns active departments keyed by ID with one database query."
  @spec list_depts_by_ids(list()) :: [SysDept.t()]
  def list_depts_by_ids(ids) when is_list(ids) do
    ids = ids |> Enum.map(&parse_positive_integer/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      []
    else
      from(d in SysDept, where: d.deleted == false and d.dept_id in ^ids)
      |> Repo.all()
    end
  end

  def list_depts_by_ids(_ids), do: []

  def create_dept(attrs, options)

  def create_dept(attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_create(options) do
      do_create_dept(attrs, KeystonePhoenix.Authz.Command.actor_id(options))
    end
  end

  def create_dept(_attrs, _options), do: {:error, :authorization_required}

  defp do_create_dept(attrs, actor_id) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, parent_id} <- positive_parent_id(attrs[:parent_id]),
         :ok <- ensure_name_available(attrs[:dept_name], parent_id, nil),
         {:ok, ancestors} <- build_ancestors(parent_id) do
      attrs = Map.merge(attrs, %{parent_id: parent_id, ancestors: ancestors})

      attrs
      |> then(&SysDept.changeset(%SysDept{}, &1))
      |> Audit.put_actor(:creator_id, actor_id)
      |> Repo.insert()
    end
  end

  def update_dept(id, attrs, options)

  def update_dept(id, attrs, options) when is_map(attrs) and is_list(options) do
    with :ok <- Authorization.authorize_target(options, "system:dept:edit", id) do
      do_update_dept(id, attrs, KeystonePhoenix.Authz.Command.actor_id(options))
    end
  end

  def update_dept(_id, _attrs, _options), do: {:error, :authorization_required}

  defp do_update_dept(id, attrs, actor_id) when is_map(attrs) do
    with {:ok, dept} <- get_dept(id),
         attrs <- normalize_attrs(attrs),
         {:ok, parent_id} <- positive_parent_id(Map.get(attrs, :parent_id, dept.parent_id)),
         :ok <- ensure_not_descendant(dept, parent_id),
         :ok <-
           ensure_name_available(attrs[:dept_name] || dept.dept_name, parent_id, dept.dept_id),
         {:ok, ancestors} <- build_ancestors(parent_id),
         :ok <- ensure_status_change_allowed(dept, attrs) do
      attrs = Map.merge(attrs, %{parent_id: parent_id, ancestors: ancestors})
      changeset = SysDept.changeset(dept, attrs) |> Audit.put_actor(:updater_id, actor_id)
      update_with_descendants(dept, changeset, ancestors)
    else
      error -> error
    end
  end

  def delete_dept(id, options)

  def delete_dept(id, options) when is_list(options) do
    with :ok <- Authorization.authorize_target(options, "system:dept:remove", id) do
      do_delete_dept(id, KeystonePhoenix.Authz.Command.actor_id(options))
    end
  end

  def delete_dept(_id, _options), do: {:error, :authorization_required}

  defp do_delete_dept(id, actor_id) do
    with {:ok, dept} <- get_dept(id) do
      cond do
        child_count(dept.dept_id) > 0 ->
          {:error, :has_children}

        user_count(dept.dept_id) > 0 ->
          {:error, :has_users}

        true ->
          changeset = Ecto.Changeset.change(dept, deleted: true)
          changeset = Audit.put_actor(changeset, :updater_id, actor_id)

          case Repo.update(changeset) do
            {:ok, _deleted} -> :ok
            {:error, _changeset} -> {:error, :update_failed}
          end
      end
    else
      error -> error
    end
  end

  def dept_to_map(dept) do
    %{
      "deptId" => dept.dept_id,
      "id" => dept.dept_id,
      "parentId" => dept.parent_id,
      "ancestors" => dept.ancestors,
      "deptName" => dept.dept_name,
      "orderNum" => dept.order_num,
      "leaderId" => dept.leader_id,
      "leaderName" => dept.leader_name,
      "phone" => dept.phone,
      "email" => dept.email,
      "status" => dept.status,
      "statusStr" => status_label(dept.status),
      "createTime" => format_datetime(dept.create_time)
    }
  end

  defp normalize_attrs(attrs) do
    Enum.reduce(@dept_attrs, %{}, fn {json_key, atom_key}, normalized ->
      cond do
        Map.has_key?(attrs, json_key) -> Map.put(normalized, atom_key, Map.get(attrs, json_key))
        Map.has_key?(attrs, atom_key) -> Map.put(normalized, atom_key, Map.get(attrs, atom_key))
        true -> normalized
      end
    end)
  end

  defp positive_parent_id(nil), do: {:ok, 0}

  defp positive_parent_id(value) do
    case Params.non_negative_integer(value) do
      {:ok, parent_id} -> {:ok, parent_id}
      :error -> {:error, :invalid_parent}
    end
  end

  defp build_ancestors(0), do: {:ok, "0"}

  defp build_ancestors(parent_id) do
    case get_dept(parent_id) do
      {:ok, %{status: 1} = parent} ->
        {:ok, parent.ancestors <> "," <> Integer.to_string(parent.dept_id)}

      {:ok, _parent} ->
        {:error, :parent_disabled}

      {:error, :not_found} ->
        {:error, :parent_not_found}
    end
  end

  defp ensure_name_available(nil, _parent_id, _dept_id), do: :ok

  defp ensure_name_available(name, parent_id, dept_id) do
    query =
      from d in SysDept,
        where: d.deleted == false and d.parent_id == ^parent_id and d.dept_name == ^name

    query = if dept_id, do: where(query, [dept], dept.dept_id != ^dept_id), else: query
    if Repo.exists?(query), do: {:error, :name_exists}, else: :ok
  end

  defp ensure_not_descendant(%SysDept{dept_id: dept_id}, parent_id) when dept_id == parent_id,
    do: {:error, :invalid_parent}

  defp ensure_not_descendant(%SysDept{dept_id: dept_id}, parent_id) do
    if parent_id == 0 or not descendant_id?(dept_id, parent_id),
      do: :ok,
      else: {:error, :invalid_parent}
  end

  defp descendant_id?(ancestor_id, candidate_id) do
    case get_dept(candidate_id) do
      {:ok, candidate} -> ancestor_id in ancestor_ids(candidate.ancestors)
      {:error, :not_found} -> false
    end
  end

  defp ancestor_ids(ancestors) do
    ancestors
    |> to_string()
    |> String.split(",", trim: true)
    |> Enum.map(&parse_positive_integer/1)
    |> Enum.reject(&is_nil/1)
  end

  defp ensure_status_change_allowed(%SysDept{status: 1, dept_id: dept_id}, attrs) do
    case Params.parse_integer(attrs[:status]) do
      {:ok, 0} ->
        query =
          from child in SysDept,
            where: child.parent_id == ^dept_id and child.deleted == false and child.status == 1

        if Repo.exists?(query), do: {:error, :status_invalid}, else: :ok

      _status ->
        :ok
    end
  end

  defp ensure_status_change_allowed(_dept, _attrs), do: :ok

  defp update_with_descendants(dept, changeset, ancestors) do
    Repo.transaction(fn ->
      updated =
        case Repo.update(changeset) do
          {:ok, value} -> value
          {:error, changeset} -> Repo.rollback(changeset)
        end

      descendants =
        from(child in SysDept, where: child.deleted == false and child.dept_id != ^dept.dept_id)
        |> Repo.all()
        |> Enum.filter(&(dept.dept_id in ancestor_ids(&1.ancestors)))
        |> Enum.sort_by(&length(ancestor_ids(&1.ancestors)))

      Enum.reduce(descendants, %{dept.dept_id => ancestors}, fn child, ancestor_map ->
        parent_ancestors = Map.fetch!(ancestor_map, child.parent_id)
        child_ancestors = parent_ancestors <> "," <> Integer.to_string(child.parent_id)

        Repo.update_all(
          from(record in SysDept, where: record.dept_id == ^child.dept_id),
          set: [ancestors: child_ancestors, update_time: DateTime.utc_now()]
        )

        Map.put(ancestor_map, child.dept_id, child_ancestors)
      end)

      updated
    end)
  end

  defp child_count(parent_id) do
    from(d in SysDept, where: d.parent_id == ^parent_id and d.deleted == false)
    |> Repo.aggregate(:count, :dept_id)
  end

  defp user_count(dept_id) do
    from(u in SysUser, where: u.dept_id == ^dept_id and u.deleted == false)
    |> Repo.aggregate(:count, :user_id)
  end

  defp filter_status(query, status) do
    case Params.parse_integer(status) do
      {:ok, value} -> where(query, [dept], dept.status == ^value)
      :error -> query
    end
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp parse_positive_integer(value) when is_binary(value) do
    case Params.parse_integer(value) do
      {:ok, number} when number > 0 -> number
      _ -> nil
    end
  end

  defp parse_positive_integer(_value), do: nil

  defp status_label(1), do: "正常"
  defp status_label(0), do: "停用"
  defp status_label(status), do: to_string(status || "")

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
