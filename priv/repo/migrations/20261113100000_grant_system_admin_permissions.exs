defmodule KeystonePhoenix.Repo.Migrations.GrantSystemAdminPermissions do
  use Ecto.Migration

  @moduledoc """
  Gives the canonical system administrator role every permission currently
  registered in `sys_permission`.

  New catalog entries are also assigned by the canonical seeds, so the seeded
  administrator remains complete after a fresh bootstrap.
  """

  def up do
    execute("""
    INSERT INTO sys_role_permission (role_id, permission_id)
    SELECT 1, permission.permission_id
    FROM sys_permission permission
    WHERE EXISTS (
      SELECT 1 FROM sys_role role
      WHERE role.role_id = 1 AND role.deleted = false
    )
    ON CONFLICT (role_id, permission_id) DO NOTHING
    """)
  end

  def down do
    :ok
  end
end
