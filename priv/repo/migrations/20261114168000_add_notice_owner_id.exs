defmodule KeystonePhoenix.Repo.Migrations.AddNoticeOwnerId do
  use Ecto.Migration

  @moduledoc "为公告增加独立的所有者字段；creator_id 继续记录创建审计主体。"

  def up do
    execute("ALTER TABLE sys_notice ADD COLUMN IF NOT EXISTS owner_id uuid")

    execute("""
    UPDATE sys_notice
    SET owner_id = creator_id
    WHERE owner_id IS NULL AND creator_id IS NOT NULL
    """)

    create_if_not_exists index(:sys_notice, [:owner_id])

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'sys_notice_owner_id_fkey'
      ) THEN
        ALTER TABLE sys_notice
        ADD CONSTRAINT sys_notice_owner_id_fkey
        FOREIGN KEY (owner_id) REFERENCES sys_user (user_id) ON DELETE SET NULL;
      END IF;
    END $$;
    """)
  end

  def down do
    drop_if_exists index(:sys_notice, [:owner_id])
    execute("ALTER TABLE sys_notice DROP CONSTRAINT IF EXISTS sys_notice_owner_id_fkey")
    execute("ALTER TABLE sys_notice DROP COLUMN IF EXISTS owner_id")
  end
end
