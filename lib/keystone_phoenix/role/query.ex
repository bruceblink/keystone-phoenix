defmodule KeystonePhoenix.Role.Query do
  @moduledoc "角色列表筛选条件，供 HTTP 和 LiveView 的分页查询共用。"

  import Ecto.Query

  @doc "应用角色名称、标识和启用状态筛选。"
  def apply(query, params) do
    keyword = params["keyword"] || params["roleKeyword"] || params["roleName"] || params[:keyword]

    query
    |> filter_keyword(keyword, params["roleKey"] || params[:role_key])
    |> filter_status(params["status"] || params["roleStatus"] || params[:status])
  end

  defp filter_keyword(query, keyword, role_key) do
    keyword = present(keyword)
    role_key = present(role_key)

    cond do
      keyword != nil ->
        pattern = "%" <> keyword <> "%"
        where(query, [role], ilike(role.role_name, ^pattern) or ilike(role.role_key, ^pattern))

      role_key != nil ->
        where(query, [role], ilike(role.role_key, ^("%" <> role_key <> "%")))

      true ->
        query
    end
  end

  defp filter_status(query, value) when value in [nil, "", "all"], do: query

  defp filter_status(query, value) do
    case String.downcase(to_string(value)) do
      status when status in ["1", "true", "enabled", "active"] ->
        where(query, [role], role.status == 1)

      status when status in ["0", "false", "disabled", "inactive"] ->
        where(query, [role], role.status == 0)

      _ ->
        query
    end
  end

  defp present(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp present(_value), do: nil
end
