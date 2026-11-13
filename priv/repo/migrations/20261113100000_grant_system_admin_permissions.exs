defmodule KeystonePhoenix.Repo.Migrations.GrantSystemAdminPermissions do
  use Ecto.Migration

  alias KeystonePhoenix.Authz.PermissionCatalog

  @moduledoc """
  Gives the canonical system administrator role every permission currently
  registered in `sys_permission`.

  New catalog entries are also assigned by the canonical seeds, so the seeded
  administrator remains complete after a fresh bootstrap.
  """

  def up do
    now = DateTime.utc_now()

    permission_entries =
      Enum.map(PermissionCatalog.entries(), fn entry ->
        entry
        |> Map.take([:permission, :resource, :domain, :action, :description, :deprecated])
        |> Map.put(:risk, Atom.to_string(entry.risk))
        |> Map.merge(%{status: 1, create_time: now, update_time: now})
      end)

    repo().insert_all("sys_permission", permission_entries,
      on_conflict: :nothing,
      conflict_target: :permission
    )

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
