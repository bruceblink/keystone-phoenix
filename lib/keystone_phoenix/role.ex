defmodule KeystonePhoenix.Role do
  @moduledoc "Query boundary for role and role-menu permissions."

  import Ecto.Query

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.{SysRole, SysRoleMenu}

  def list_roles(params \\ %{}) do
    query =
      from(r in SysRole,
        where: r.deleted == false,
        order_by: [asc: r.role_sort, asc: r.role_id]
      )

    query = filter_contains(query, :role_name, params["roleName"] || params[:role_name])
    query = filter_contains(query, :role_key, params["roleKey"] || params[:role_key])
    query = filter_status(query, params["status"] || params[:status])
    page = positive_integer(params["pageNum"] || params[:page_num], 1)
    page_size = min(positive_integer(params["pageSize"] || params[:page_size], 10), 500)
    total = Repo.aggregate(query, :count, :role_id)
    rows = query |> limit(^page_size) |> offset(^((page - 1) * page_size)) |> Repo.all()
    %{total: total, rows: Enum.map(rows, &role_to_map/1)}
  end

  def get_role(id) do
    case Repo.get_by(SysRole, role_id: id, deleted: false) do
      nil -> {:error, :not_found}
      role -> {:ok, role}
    end
  end

  def menu_ids_for_role(role_id) do
    from(rm in SysRoleMenu, where: rm.role_id == ^role_id, select: rm.menu_id)
    |> Repo.all()
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

  defp positive_integer(nil, default), do: default

  defp positive_integer(value, default) do
    case Integer.parse(to_string(value)) do
      {number, ""} when number > 0 -> number
      _ -> default
    end
  end

  defp format_datetime(nil), do: nil

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")

  defp format_datetime(%NaiveDateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
end
