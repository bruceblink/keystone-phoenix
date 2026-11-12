defmodule KeystonePhoenix.Authz.SysRolePermission do
  @moduledoc "PostgreSQL schema for normalized role to permission bindings."

  use Ecto.Schema

  @primary_key false

  schema "sys_role_permission" do
    field :role_id, :integer, primary_key: true
    field :permission_id, :integer, primary_key: true
  end
end
