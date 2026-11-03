defmodule KeystonePhoenix.Department do
  @moduledoc "Query boundary for department management."

  import Ecto.Query

  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Repo
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
    depts = list_depts()
    Enum.filter(depts, &(&1["parentId"] == 0)) |> Enum.map(&attach_children(&1, depts))
  end

  def get_dept(id) do
    case Repo.get_by(SysDept, dept_id: id, deleted: false) do
      nil -> {:error, :not_found}
      dept -> {:ok, dept}
    end
  end

  def create_dept(attrs) when is_map(attrs) do
    attrs = normalize_attrs(attrs)

    with {:ok, parent_id} <- positive_parent_id(attrs[:parent_id]),
         {:ok, ancestors} <- build_ancestors(parent_id) do
      attrs = Map.merge(attrs, %{parent_id: parent_id, ancestors: ancestors})
      Repo.insert(SysDept.changeset(%SysDept{}, attrs))
    end
  end

  def create_dept(_attrs), do: {:error, invalid_changeset(:dept_name)}

  def update_dept(id, attrs) when is_map(attrs) do
    with {:ok, dept} <- get_dept(id),
         attrs <- normalize_attrs(attrs),
         {:ok, parent_id} <- positive_parent_id(Map.get(attrs, :parent_id, dept.parent_id)) do
      if parent_id == dept.dept_id do
        {:error, :invalid_parent}
      else
        with {:ok, ancestors} <- build_ancestors(parent_id) do
          attrs = Map.merge(attrs, %{parent_id: parent_id, ancestors: ancestors})
          Repo.update(SysDept.changeset(dept, attrs))
        end
      end
    else
      error -> error
    end
  end

  def update_dept(_id, _attrs), do: {:error, invalid_changeset(:dept_name)}

  def delete_dept(id) do
    with {:ok, dept} <- get_dept(id) do
      cond do
        child_count(dept.dept_id) > 0 ->
          {:error, :has_children}

        user_count(dept.dept_id) > 0 ->
          {:error, :has_users}

        true ->
          case Repo.update(Ecto.Changeset.change(dept, deleted: true)) do
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
      "parentId" => dept.parent_id,
      "ancestors" => dept.ancestors,
      "deptName" => dept.dept_name,
      "orderNum" => dept.order_num,
      "leaderId" => dept.leader_id,
      "leaderName" => dept.leader_name,
      "phone" => dept.phone,
      "email" => dept.email,
      "status" => dept.status,
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
    case Integer.parse(to_string(value)) do
      {parent_id, ""} when parent_id >= 0 -> {:ok, parent_id}
      _ -> {:error, :invalid_parent}
    end
  end

  defp build_ancestors(0), do: {:ok, "0"}

  defp build_ancestors(parent_id) do
    case get_dept(parent_id) do
      {:ok, parent} -> {:ok, parent.ancestors <> "," <> Integer.to_string(parent.dept_id)}
      {:error, :not_found} -> {:error, :parent_not_found}
    end
  end

  defp child_count(parent_id) do
    from(d in SysDept, where: d.parent_id == ^parent_id and d.deleted == false)
    |> Repo.aggregate(:count, :dept_id)
  end

  defp user_count(dept_id) do
    from(u in SysUser, where: u.dept_id == ^dept_id and u.deleted == false)
    |> Repo.aggregate(:count, :user_id)
  end

  defp invalid_changeset(field),
    do: Ecto.Changeset.add_error(Ecto.Changeset.change(%SysDept{}), field, "参数无效")

  defp attach_children(dept, depts) do
    children =
      depts
      |> Enum.filter(&(&1["parentId"] == dept["deptId"]))
      |> Enum.map(&attach_children(&1, depts))

    if children == [], do: dept, else: Map.put(dept, "children", children)
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, ""), do: query

  defp filter_status(query, status) do
    case Integer.parse(to_string(status)) do
      {value, ""} -> where(query, [dept], dept.status == ^value)
      _ -> query
    end
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
