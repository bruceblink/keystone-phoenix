defmodule KeystonePhoenix.Authz.Capabilities do
  @moduledoc "为当前人类会话计算权限集合和资源列表范围。"

  import Ecto.Query
  require Logger

  alias KeystonePhoenix.Authz.{PermissionCatalog, ResourceScope, SysPermission, SysRolePermission}
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole
  alias KeystonePhoenix.User.SysUserRole

  @permission_names PermissionCatalog.permissions()
  @resources [
    {"user", :user},
    {"department", :department},
    {"role", :role},
    {"post", :post},
    {"menu", :menu},
    {"config", :config},
    {"dictionary", :dictionary},
    {"notice", :notice},
    {"job", :job},
    {"audit", :audit},
    {"session", :session},
    {"api-key", :api_key},
    {"profile", :profile}
  ]

  @doc "每次请求从数据库读取当前角色和权限；依赖故障返回错误，不伪装为空权限。"
  def for_user(%{user_id: user_id} = user) when is_binary(user_id) do
    with {:ok, role_ids} <- role_ids(user_id, user.role_id),
         {:ok, active_roles} <- active_roles(role_ids),
         {:ok, permissions} <- active_permissions(active_roles) do
      data_scopes = Enum.map(active_roles, & &1.data_scope)

      resources =
        Map.new(@resources, fn {name, resource} ->
          {name, ResourceScope.allowed_for_scopes?(resource, data_scopes)}
        end)

      {:ok, %{permissions: permissions, resources: resources}}
    end
  rescue
    error ->
      # 只记录异常类型，不展开消息，避免日志写入 SQL 参数或用户信息。
      Logger.warning("Capabilities authorization read failed (#{error_class(error)})")
      {:error, :authorization_unavailable}
  end

  def for_user(_user), do: {:error, :authorization_unavailable}

  defp error_class(%{__struct__: module}), do: inspect(module)

  defp role_ids(user_id, legacy_role_id) do
    ids =
      from(membership in SysUserRole,
        where: membership.user_id == ^user_id,
        order_by: membership.role_id,
        select: membership.role_id
      )
      |> Repo.all()

    {:ok, if(ids == [], do: List.wrap(legacy_role_id), else: Enum.uniq(ids))}
  end

  defp active_roles([]), do: {:ok, []}

  defp active_roles(role_ids) do
    roles =
      from(role in SysRole,
        where: role.role_id in ^role_ids and role.deleted == false and role.status == 1,
        select: %{role_id: role.role_id, data_scope: role.data_scope}
      )
      |> Repo.all()

    {:ok, roles}
  end

  defp active_permissions([]), do: {:ok, []}

  defp active_permissions(active_roles) do
    role_ids = Enum.map(active_roles, & &1.role_id)

    permissions =
      from(permission in SysPermission,
        join: binding in SysRolePermission,
        on: binding.permission_id == permission.permission_id,
        where:
          binding.role_id in ^role_ids and permission.permission in ^@permission_names and
            permission.status == 1 and permission.deprecated == false,
        distinct: true,
        order_by: permission.permission,
        select: permission.permission
      )
      |> Repo.all()

    {:ok, permissions}
  end
end
