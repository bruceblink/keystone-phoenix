defmodule KeystonePhoenix.Repo.Migrations.CreatePermissionCatalogTables do
  use Ecto.Migration

  def up do
    create table(:sys_permission, primary_key: false) do
      add :permission_id, :bigserial, primary_key: true
      add :permission, :string, size: 128, null: false
      add :resource, :string, size: 64, null: false
      add :domain, :string, size: 64, null: false
      add :action, :string, size: 64, null: false
      add :description, :string, size: 256, null: false, default: ""
      add :risk, :string, size: 16, null: false, default: "low"
      add :deprecated, :boolean, null: false, default: false
      add :status, :smallint, null: false, default: 1

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create unique_index(:sys_permission, [:permission],
             name: :sys_permission_permission_unique_index
           )

    create index(:sys_permission, [:resource, :domain, :action],
             name: :sys_permission_action_index
           )

    create table(:sys_role_permission, primary_key: false) do
      add :role_id,
          references(:sys_role, column: :role_id, type: :bigint, on_delete: :delete_all),
          null: false

      add :permission_id,
          references(:sys_permission,
            column: :permission_id,
            type: :bigint,
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:sys_role_permission, [:role_id, :permission_id],
             name: :sys_role_permission_role_id_permission_id_unique_index
           )

    backfill_permissions()
  end

  def down do
    drop table(:sys_role_permission)
    drop table(:sys_permission)
  end

  defp backfill_permissions do
    execute("""
    INSERT INTO sys_permission
      (permission, resource, domain, action, description, risk, deprecated, status, create_time, update_time)
    SELECT DISTINCT ON (trim(menu.permission))
      trim(menu.permission),
      split_part(trim(menu.permission), ':', 1),
      split_part(trim(menu.permission), ':', 2),
      split_part(trim(menu.permission), ':', 3),
      '',
      CASE
        WHEN split_part(trim(menu.permission), ':', 3) IN ('remove', 'resetPwd', 'forceLogout') THEN 'high'
        WHEN split_part(trim(menu.permission), ':', 3) IN ('add', 'edit', 'changeStatus', 'run') THEN 'medium'
        ELSE 'low'
      END,
      false,
      1,
      CURRENT_TIMESTAMP,
      CURRENT_TIMESTAMP
    FROM sys_menu menu
    WHERE menu.permission IS NOT NULL
      AND trim(menu.permission) <> ''
      AND array_length(string_to_array(trim(menu.permission), ':'), 1) = 3
    ORDER BY trim(menu.permission), menu.menu_id
    ON CONFLICT (permission) DO NOTHING
    """)

    execute("""
    INSERT INTO sys_role_permission (role_id, permission_id)
    SELECT DISTINCT role_menu.role_id, permission.permission_id
    FROM sys_role_menu role_menu
    JOIN sys_menu menu ON menu.menu_id = role_menu.menu_id
    JOIN sys_permission permission ON permission.permission = trim(menu.permission)
    ON CONFLICT (role_id, permission_id) DO NOTHING
    """)
  end
end
