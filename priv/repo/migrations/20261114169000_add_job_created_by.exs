defmodule KeystonePhoenix.Repo.Migrations.AddJobCreatedBy do
  use Ecto.Migration

  @moduledoc "为任务增加独立的创建主体字段；creator_id 继续记录创建审计主体。"

  def up do
    execute("ALTER TABLE sys_job ADD COLUMN IF NOT EXISTS created_by uuid")

    execute("""
    UPDATE sys_job
    SET created_by = creator_id
    WHERE created_by IS NULL AND creator_id IS NOT NULL
    """)

    create_if_not_exists index(:sys_job, [:created_by])

    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'sys_job_created_by_fkey'
      ) THEN
        ALTER TABLE sys_job
        ADD CONSTRAINT sys_job_created_by_fkey
        FOREIGN KEY (created_by) REFERENCES sys_user (user_id) ON DELETE SET NULL;
      END IF;
    END $$;
    """)
  end

  def down do
    drop_if_exists index(:sys_job, [:created_by])
    execute("ALTER TABLE sys_job DROP CONSTRAINT IF EXISTS sys_job_created_by_fkey")
    execute("ALTER TABLE sys_job DROP COLUMN IF EXISTS created_by")
  end
end
