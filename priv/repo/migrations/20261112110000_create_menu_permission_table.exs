defmodule KeystonePhoenix.Repo.Migrations.CreateMenuPermissionTable do
  use Ecto.Migration

  def up do
    create table(:sys_menu_permission, primary_key: false) do
      add :menu_id,
          references(:sys_menu, column: :menu_id, type: :bigint, on_delete: :delete_all),
          null: false

      add :permission_id,
          references(:sys_permission,
            column: :permission_id,
            type: :bigint,
            on_delete: :delete_all
          ),
          null: false
    end

    create unique_index(:sys_menu_permission, [:menu_id, :permission_id],
             name: :sys_menu_permission_menu_id_permission_id_unique_index
           )

    execute("""
    INSERT INTO sys_menu_permission (menu_id, permission_id)
    SELECT menu.menu_id, permission.permission_id
    FROM sys_menu menu
    JOIN sys_permission permission ON permission.permission = trim(menu.permission)
    WHERE menu.permission IS NOT NULL AND trim(menu.permission) <> ''
    ON CONFLICT (menu_id, permission_id) DO NOTHING
    """)

    alter table(:sys_menu) do
      remove :permission
    end
  end

  def down do
    alter table(:sys_menu) do
      add :permission, :string, size: 128
    end

    execute("""
    UPDATE sys_menu menu
    SET permission = permission.permission
    FROM sys_menu_permission menu_permission
    JOIN sys_permission permission ON permission.permission_id = menu_permission.permission_id
    WHERE menu.menu_id = menu_permission.menu_id
    """)

    drop table(:sys_menu_permission)
  end
end
