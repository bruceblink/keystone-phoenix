defmodule KeystonePhoenix.AdminScopeTestSupport do
  @moduledoc "测试专用的管理员数据范围主体构造器。它读取测试数据库中的真实 admin 角色，并保留调用方指定的主体身份和权限。"

  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.Role.SysRole

  @doc "返回引用真实 admin 角色的主体；权限列表由各测试按场景明确设置。"
  def all_scope_principal(attrs \\ %{}) when is_map(attrs) do
    role = Repo.get_by!(SysRole, role_key: "admin", deleted: false)

    unless role.status == 1 and role.data_scope == "ALL" do
      raise "测试数据库的 admin 角色必须启用并具有 ALL 数据范围"
    end

    defaults = %{
      user_id: Identity.v5(Identity.permission_namespace(), "system:user:admin"),
      role_id: role.role_id
    }

    Map.merge(defaults, attrs)
  end
end
