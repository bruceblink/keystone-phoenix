defmodule KeystonePhoenix.Repo.Migrations.AddUuidPostMenuActorForeignKeys do
  use Ecto.Migration

  @moduledoc """
  为 UUID 岗位和菜单补充创建者、修改者外键。

  该迁移单独追加约束，避免修改已经执行的身份迁移。重复执行时，已有约束保持不变。
  """

  def up do
    add_foreign_key("sys_post", "sys_post_creator_id_fkey", "creator_id")
    add_foreign_key("sys_post", "sys_post_updater_id_fkey", "updater_id")
    add_foreign_key("sys_menu", "sys_menu_creator_id_fkey", "creator_id")
    add_foreign_key("sys_menu", "sys_menu_updater_id_fkey", "updater_id")
  end

  def down do
    execute("ALTER TABLE sys_post DROP CONSTRAINT IF EXISTS sys_post_creator_id_fkey")
    execute("ALTER TABLE sys_post DROP CONSTRAINT IF EXISTS sys_post_updater_id_fkey")
    execute("ALTER TABLE sys_menu DROP CONSTRAINT IF EXISTS sys_menu_creator_id_fkey")
    execute("ALTER TABLE sys_menu DROP CONSTRAINT IF EXISTS sys_menu_updater_id_fkey")
  end

  defp add_foreign_key(table, constraint, column) do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = '#{constraint}'
          AND conrelid = '#{table}'::regclass
      ) THEN
        EXECUTE 'ALTER TABLE #{table} ADD CONSTRAINT #{constraint} '
          || 'FOREIGN KEY (#{column}) REFERENCES sys_user(user_id) ON DELETE SET NULL';
      END IF;
    END $$;
    """)
  end
end
