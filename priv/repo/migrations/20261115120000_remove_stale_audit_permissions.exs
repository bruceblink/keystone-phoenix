defmodule KeystonePhoenix.Repo.Migrations.RemoveStaleAuditPermissions do
  use Ecto.Migration

  @moduledoc "Removes audit permissions without a corresponding management interface."

  def up do
    execute("""
    DELETE FROM sys_menu_permission
    WHERE permission_id IN (
      SELECT permission_id FROM sys_permission
      WHERE permission IN ('audit:delete', 'audit:export')
    )
    """)

    execute("""
    DELETE FROM sys_role_permission
    WHERE permission_id IN (
      SELECT permission_id FROM sys_permission
      WHERE permission IN ('audit:delete', 'audit:export')
    )
    """)

    execute("""
    DELETE FROM sys_permission
    WHERE permission IN ('audit:delete', 'audit:export')
    """)
  end

  def down, do: :ok
end
