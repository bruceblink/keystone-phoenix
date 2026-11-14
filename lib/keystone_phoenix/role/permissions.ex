defmodule KeystonePhoenix.Role.Permissions do
  @moduledoc "角色与规范权限目录的绑定。"

  import Ecto.Query

  alias KeystonePhoenix.Authz.{SysPermission, SysRolePermission}
  alias KeystonePhoenix.Role.Authorization
  alias KeystonePhoenix.Params
  alias KeystonePhoenix.Repo

  @doc "返回角色当前启用的权限标识。"
  def list(role_id) do
    from(binding in SysRolePermission,
      join: permission in SysPermission,
      on: permission.permission_id == binding.permission_id,
      where:
        binding.role_id == ^role_id and permission.status == 1 and
          permission.deprecated == false,
      order_by: [asc: permission.permission],
      select: permission.permission
    )
    |> Repo.all()
  end

  def list_for_role(role_id, options) when is_list(options) do
    with :ok <- Authorization.authorize_read(options, "role:read") do
      {:ok, list(role_id)}
    end
  end

  @doc "替换角色权限。输入可以是权限标识或权限目录 UUID。"
  def replace(role_id, permissions) when is_list(permissions) do
    with {:ok, permission_ids} <- resolve(permissions) do
      Repo.delete_all(from(binding in SysRolePermission, where: binding.role_id == ^role_id))

      if permission_ids != [] do
        Repo.insert_all(
          SysRolePermission,
          Enum.map(permission_ids, fn permission_id ->
            %{role_id: role_id, permission_id: permission_id}
          end)
        )
      end

      :ok
    end
  end

  def replace(_role_id, _permissions), do: {:error, :permission_not_found}

  def replace_in_transaction(role_id, permissions) do
    case replace(role_id, permissions) do
      :ok -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  def from_attrs(attrs) do
    cond do
      Map.has_key?(attrs, "permissions") -> normalize_values(Map.get(attrs, "permissions"))
      Map.has_key?(attrs, :permissions) -> normalize_values(Map.get(attrs, :permissions))
      true -> nil
    end
  end

  defp resolve(values) do
    values = values |> Enum.map(&normalize/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    codes = Enum.filter(values, &String.contains?(&1, ":"))

    ids =
      Enum.flat_map(values, fn value ->
        if String.contains?(value, ":"), do: [], else: List.wrap(parse_uuid(value))
      end)

    query =
      from(permission in SysPermission,
        where: permission.status == 1 and permission.deprecated == false
      )

    query =
      cond do
        codes != [] and ids != [] ->
          where(
            query,
            [permission],
            permission.permission in ^codes or permission.permission_id in ^ids
          )

        codes != [] ->
          where(query, [permission], permission.permission in ^codes)

        ids != [] ->
          where(query, [permission], permission.permission_id in ^ids)

        true ->
          query
      end

    records =
      query
      |> select([permission], {permission.permission, permission.permission_id})
      |> Repo.all()

    by_value =
      Enum.reduce(records, %{}, fn {permission, permission_id}, acc ->
        acc
        |> Map.put(permission, permission_id)
        |> Map.put(to_string(permission_id), permission_id)
      end)

    if Enum.all?(values, &Map.has_key?(by_value, &1)) do
      {:ok, Enum.map(values, &Map.fetch!(by_value, &1))}
    else
      {:error, :permission_not_found}
    end
  end

  defp normalize(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        nil

      String.contains?(value, ":") ->
        value

      true ->
        case Params.parse_uuid(value) do
          {:ok, uuid} -> uuid
          :error -> value
        end
    end
  end

  defp normalize(value), do: to_string(value)

  defp parse_uuid(value) do
    case Params.parse_uuid(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp normalize_values(values) when is_binary(values), do: String.split(values, ",", trim: true)
  defp normalize_values(values) when is_list(values), do: values
  defp normalize_values(_values), do: []
end
