defmodule KeystonePhoenix.Repo.Migrations.RebuildCoreIdentityIdsAsUuid do
  use Ecto.Migration

  @moduledoc """
  一次性重建核心身份表的主键和直接关系。

  新版本不保留整数 ID 的数据兼容层。迁移在检测到旧整数结构时清空受影响
  的系统数据，再把核心身份列改为 PostgreSQL uuid。应用层在写入时生成 UUIDv7。
  """

  def up do
    unless core_uuid_ready?() do
      # 旧整数关系无法与新 uuid 外键共存。一次性重构允许清空旧系统数据，
      # 避免把旧数字值伪装成新的身份标识。
      execute(
        "TRUNCATE TABLE sys_role_permission, sys_role_menu, sys_menu_permission, auth_sessions, sys_operation_log, sys_user, sys_role, sys_dept CASCADE"
      )

      drop_identity_foreign_keys()
      alter_core_columns()
      create_identity_foreign_keys()
    end
  end

  def down do
    # 旧整数身份不可逆转换。回滚边界是恢复应用版本和数据库备份。
    :ok
  end

  defp core_uuid_ready? do
    repo().query!("""
    SELECT COUNT(*) AS count
    FROM information_schema.columns
    WHERE table_schema = current_schema()
      AND data_type = 'uuid'
      AND (table_name, column_name) IN (
        ('sys_user', 'user_id'), ('sys_user', 'role_id'), ('sys_user', 'dept_id'),
        ('sys_user', 'creator_id'), ('sys_user', 'updater_id'),
        ('sys_role', 'role_id'), ('sys_role', 'creator_id'), ('sys_role', 'updater_id'),
        ('sys_dept', 'dept_id'), ('sys_dept', 'parent_id'), ('sys_dept', 'leader_id'),
        ('sys_dept', 'creator_id'), ('sys_dept', 'updater_id'),
        ('sys_role_menu', 'role_id'), ('sys_role_permission', 'role_id'),
        ('auth_sessions', 'user_id'),
        ('sys_operation_log', 'user_id'), ('sys_operation_log', 'dept_id')
      )
    """).rows == [[18]]
  end

  defp drop_identity_foreign_keys do
    execute("""
    DO $$
    DECLARE item record;
    BEGIN
      FOR item IN
        SELECT conrelid::regclass AS table_name, conname AS constraint_name
        FROM pg_constraint
        WHERE contype = 'f'
          AND (confrelid IN ('sys_user'::regclass, 'sys_role'::regclass, 'sys_dept'::regclass)
               OR conrelid IN ('sys_user'::regclass, 'sys_role'::regclass, 'sys_dept'::regclass,
                               'sys_role_menu'::regclass, 'sys_role_permission'::regclass,
                               'auth_sessions'::regclass, 'sys_operation_log'::regclass))
      LOOP
        EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I',
                       item.table_name, item.constraint_name);
      END LOOP;
    END $$;
    """)
  end

  defp alter_core_columns do
    for {table, columns} <- [
          {"sys_user", ~w(user_id role_id dept_id creator_id updater_id)},
          {"sys_role", ~w(role_id creator_id updater_id)},
          {"sys_dept", ~w(dept_id parent_id leader_id creator_id updater_id)},
          {"sys_role_menu", ~w(role_id)},
          {"sys_role_permission", ~w(role_id)},
          {"auth_sessions", ~w(user_id)},
          {"sys_operation_log", ~w(user_id dept_id)}
        ] do
      for column <- columns do
        execute("ALTER TABLE #{table} ALTER COLUMN #{column} DROP DEFAULT")
        execute("ALTER TABLE #{table} ALTER COLUMN #{column} TYPE uuid USING NULL::uuid")
      end
    end

    execute("ALTER TABLE sys_dept ALTER COLUMN parent_id DROP NOT NULL")
    execute("ALTER TABLE sys_dept ALTER COLUMN ancestors SET DEFAULT ''")
  end

  defp create_identity_foreign_keys do
    execute(
      "ALTER TABLE sys_user ADD CONSTRAINT sys_user_role_id_fkey FOREIGN KEY (role_id) REFERENCES sys_role(role_id) ON DELETE SET NULL"
    )

    execute(
      "ALTER TABLE sys_user ADD CONSTRAINT sys_user_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES sys_dept(dept_id) ON DELETE SET NULL"
    )

    execute(
      "ALTER TABLE sys_dept ADD CONSTRAINT sys_dept_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES sys_dept(dept_id) ON DELETE SET NULL"
    )

    execute(
      "ALTER TABLE sys_dept ADD CONSTRAINT sys_dept_leader_id_fkey FOREIGN KEY (leader_id) REFERENCES sys_user(user_id) ON DELETE SET NULL"
    )

    execute(
      "ALTER TABLE sys_role_menu ADD CONSTRAINT sys_role_menu_role_id_fkey FOREIGN KEY (role_id) REFERENCES sys_role(role_id) ON DELETE CASCADE"
    )

    execute(
      "ALTER TABLE sys_role_permission ADD CONSTRAINT sys_role_permission_role_id_fkey FOREIGN KEY (role_id) REFERENCES sys_role(role_id) ON DELETE CASCADE"
    )

    execute(
      "ALTER TABLE auth_sessions ADD CONSTRAINT auth_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES sys_user(user_id) ON DELETE CASCADE"
    )

    execute(
      "ALTER TABLE sys_operation_log ADD CONSTRAINT sys_operation_log_user_id_fkey FOREIGN KEY (user_id) REFERENCES sys_user(user_id) ON DELETE SET NULL"
    )

    execute(
      "ALTER TABLE sys_operation_log ADD CONSTRAINT sys_operation_log_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES sys_dept(dept_id) ON DELETE SET NULL"
    )
  end
end
