defmodule KeystonePhoenix.Role.NativeQuery do
  @moduledoc "Native 角色列表查询，不受 LiveView 分页上限影响。"

  import Ecto.Query

  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role
  alias KeystonePhoenix.Role.SysRole

  def list_all(params, options) when is_map(params) and is_list(options) do
    with :ok <- Role.Authorization.authorize_read(options, "role:read") do
      query =
        from(r in SysRole,
          where: r.deleted == false,
          order_by: [asc: r.role_sort, asc: r.role_id]
        )

      query = filter_contains(query, :role_name, params["roleName"] || params[:role_name])
      query = filter_contains(query, :role_key, params["roleKey"] || params[:role_key])
      query = filter_status(query, params["status"] || params[:status])
      {:ok, Repo.all(query) |> Enum.map(&Role.role_to_map/1)}
    end
  end

  defp filter_contains(query, _field, nil), do: query
  defp filter_contains(query, _field, ""), do: query

  defp filter_contains(query, field, value) do
    where(
      query,
      [role],
      ilike(field(role, ^field), ^("%" <> String.trim(to_string(value)) <> "%"))
    )
  end

  defp filter_status(query, nil), do: query
  defp filter_status(query, ""), do: query

  defp filter_status(query, value) do
    case Integer.parse(to_string(value)) do
      {status, ""} -> where(query, [role], role.status == ^status)
      _ -> query
    end
  end
end
