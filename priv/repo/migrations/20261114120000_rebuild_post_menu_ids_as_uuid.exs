defmodule KeystonePhoenix.Repo.Migrations.RebuildPostMenuIdsAsUuid do
  use Ecto.Migration

  alias KeystonePhoenix.Identity

  @moduledoc """
  一次性重建岗位和菜单身份列。

  旧整数岗位、菜单和关联数据属于可破坏的系统初始化数据。迁移先清空这些
  记录，再把主键、父子关系和菜单关联改为 PostgreSQL uuid，并写入固定启动记录。
  """

  def up do
    unless uuid_ready?() do
      drop_foreign_keys()
      execute("UPDATE sys_user SET post_id = NULL")
      execute("TRUNCATE TABLE sys_menu_permission, sys_role_menu, sys_menu, sys_post CASCADE")
      alter_identity_columns()
      create_foreign_keys()
    end

    ensure_bootstrap_records()
  end

  def down do
    # 整数身份不可逆转换。回滚边界是恢复应用版本和数据库备份。
    :ok
  end

  defp uuid_ready? do
    %{rows: [[count]]} =
      repo().query!("""
      SELECT COUNT(*)
      FROM information_schema.columns
      WHERE table_schema = current_schema()
        AND data_type = 'uuid'
        AND ((table_name = 'sys_post' AND column_name = 'post_id')
          OR (table_name = 'sys_menu' AND column_name IN ('menu_id', 'parent_id'))
          OR (table_name = 'sys_role_menu' AND column_name = 'menu_id')
          OR (table_name = 'sys_menu_permission' AND column_name = 'menu_id')
          OR (table_name = 'sys_user' AND column_name = 'post_id'))
      """)

    count == 6
  end

  defp drop_foreign_keys do
    execute("""
    DO $$
    DECLARE item record;
    BEGIN
      FOR item IN
        SELECT conrelid::regclass AS table_name, conname AS constraint_name
        FROM pg_constraint
        WHERE contype = 'f'
          AND (conrelid IN ('sys_post'::regclass, 'sys_menu'::regclass,
                            'sys_role_menu'::regclass, 'sys_menu_permission'::regclass,
                            'sys_user'::regclass)
               OR confrelid IN ('sys_post'::regclass, 'sys_menu'::regclass))
      LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I',
                       item.table_name, item.constraint_name);
      END LOOP;
    END $$;
    """)
  end

  defp alter_identity_columns do
    for {table, columns} <- [
          {"sys_user", ["post_id"]},
          {"sys_post", ["post_id", "creator_id", "updater_id"]},
          {"sys_menu", ["menu_id", "parent_id", "creator_id", "updater_id"]},
          {"sys_role_menu", ["menu_id"]},
          {"sys_menu_permission", ["menu_id"]}
        ] do
      for column <- columns do
        execute("ALTER TABLE #{table} ALTER COLUMN #{column} DROP DEFAULT")
        execute("ALTER TABLE #{table} ALTER COLUMN #{column} TYPE uuid USING NULL::uuid")
      end
    end

    execute("ALTER TABLE sys_menu ALTER COLUMN parent_id DROP NOT NULL")
  end

  defp create_foreign_keys do
    execute("""
    ALTER TABLE sys_user
      ADD CONSTRAINT sys_user_post_id_fkey
      FOREIGN KEY (post_id) REFERENCES sys_post(post_id) ON DELETE SET NULL
    """)

    execute("""
    ALTER TABLE sys_menu
      ADD CONSTRAINT sys_menu_parent_id_fkey
      FOREIGN KEY (parent_id) REFERENCES sys_menu(menu_id) ON DELETE SET NULL
    """)

    execute("""
    ALTER TABLE sys_role_menu
      ADD CONSTRAINT sys_role_menu_menu_id_fkey
      FOREIGN KEY (menu_id) REFERENCES sys_menu(menu_id) ON DELETE CASCADE
    """)

    execute("""
    ALTER TABLE sys_menu_permission
      ADD CONSTRAINT sys_menu_permission_menu_id_fkey
      FOREIGN KEY (menu_id) REFERENCES sys_menu(menu_id) ON DELETE CASCADE
    """)
  end

  defp ensure_bootstrap_records do
    namespace = Identity.permission_namespace()
    post_ceo = Identity.v5(namespace, "system:post:ceo")
    post_engineer = Identity.v5(namespace, "system:post:engineer")
    menu_system = Identity.v5(namespace, "system:menu:system")
    menu_users = Identity.v5(namespace, "system:menu:users")

    execute("""
    INSERT INTO sys_post
      (post_id, post_code, post_name, post_sort, status, remark, deleted, create_time, update_time)
    VALUES
      ('#{post_ceo}'::uuid, 'ceo', '董事长', 1, 1, '', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('#{post_engineer}'::uuid, 'engineer', '项目经理', 2, 1, '', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT (post_id) DO NOTHING
    """)

    execute("""
    INSERT INTO sys_menu
      (menu_id, menu_name, menu_type, router_name, parent_id, path, is_button, meta_info,
       status, remark, deleted, create_time, update_time)
    VALUES
      ('#{menu_system}'::uuid, '系统管理', 2, '', NULL, '/system', false,
       '{"title":"系统管理","showParent":true}', 1, '系统管理目录', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
      ('#{menu_users}'::uuid, '用户管理', 1, 'SystemUser', '#{menu_system}'::uuid, '/system/user/index', false,
       '{"title":"用户管理","showParent":true}', 1, '用户管理菜单', false, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT (menu_id) DO NOTHING
    """)

    execute("""
    INSERT INTO sys_role_menu (role_id, menu_id)
    SELECT role_id, '#{menu_system}'::uuid FROM sys_role WHERE role_key = 'admin' AND deleted = false
    ON CONFLICT (role_id, menu_id) DO NOTHING
    """)

    execute("""
    INSERT INTO sys_menu_permission (menu_id, permission_id)
    SELECT '#{menu_users}'::uuid, permission_id
    FROM sys_permission
    WHERE permission = 'user:read' AND status = 1 AND deprecated = false
    ON CONFLICT (menu_id, permission_id) DO NOTHING
    """)
  end
end
