defmodule KeystonePhoenix.Department do
  @moduledoc "Query boundary for department management."

  import Ecto.Query

  alias KeystonePhoenix.Department.SysDept
  alias KeystonePhoenix.Repo

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
