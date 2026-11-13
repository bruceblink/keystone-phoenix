defmodule KeystonePhoenix.Repo.Migrations.GrantSystemAdminMenus do
  use Ecto.Migration

  @moduledoc "Assigns every existing menu to the canonical system administrator role."

  def up do
    execute("""
    INSERT INTO sys_role_menu (role_id, menu_id)
    SELECT 1, menu.menu_id
    FROM sys_menu menu
    WHERE menu.deleted = false
      AND EXISTS (
        SELECT 1 FROM sys_role role
        WHERE role.role_id = 1 AND role.deleted = false
      )
    ON CONFLICT (role_id, menu_id) DO NOTHING
    """)
  end

  def down do
    execute("DELETE FROM sys_role_menu WHERE role_id = 1")
  end
end
