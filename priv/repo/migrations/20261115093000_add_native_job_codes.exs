defmodule KeystonePhoenix.Repo.Migrations.AddNativeJobCodes do
  use Ecto.Migration

  @moduledoc "Adds the independent job codes required by the Native task contract."

  def up do
    execute("ALTER TABLE sys_job ADD COLUMN IF NOT EXISTS job_code varchar(64)")
    execute("ALTER TABLE sys_job_log ADD COLUMN IF NOT EXISTS job_code varchar(64)")

    execute("""
    UPDATE sys_job
    SET job_code = 'job-' || replace(job_id::text, '-', '')
    WHERE job_code IS NULL OR btrim(job_code) = ''
    """)

    execute("""
    UPDATE sys_job_log
    SET job_code = COALESCE((SELECT job_code FROM sys_job WHERE sys_job.job_id = sys_job_log.job_id), 'job-' || replace(job_log_id::text, '-', ''))
    WHERE job_code IS NULL OR btrim(job_code) = ''
    """)

    create_if_not_exists unique_index(:sys_job, [:job_code], name: :sys_job_job_code_unique_index)
  end

  def down do
    drop_if_exists index(:sys_job, [:job_code], name: :sys_job_job_code_unique_index)
    execute("ALTER TABLE sys_job_log DROP COLUMN IF EXISTS job_code")
    execute("ALTER TABLE sys_job DROP COLUMN IF EXISTS job_code")
  end
end
