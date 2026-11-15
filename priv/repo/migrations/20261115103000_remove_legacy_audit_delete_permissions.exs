defmodule KeystonePhoenix.Repo.Migrations.RemoveLegacyAuditDeletePermissions do
  use Ecto.Migration

  @moduledoc "Removes audit delete permissions that are not part of the Native contract."

  def up do
    execute("""
    DELETE FROM sys_menu_permission
    WHERE permission_id IN (
      SELECT permission_id FROM sys_permission
      WHERE permission IN ('login-log:delete', 'operation-log:delete')
    )
    """)

    execute("""
    DELETE FROM sys_role_permission
    WHERE permission_id IN (
      SELECT permission_id FROM sys_permission
      WHERE permission IN ('login-log:delete', 'operation-log:delete')
    )
    """)

    execute("""
    DELETE FROM sys_permission
    WHERE permission IN ('login-log:delete', 'operation-log:delete')
    """)
  end

  def down, do: :ok
end
