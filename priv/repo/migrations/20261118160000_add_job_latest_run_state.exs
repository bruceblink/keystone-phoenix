defmodule KeystonePhoenix.Repo.Migrations.AddJobLatestRunState do
  use Ecto.Migration

  @moduledoc "为任务定义保存最近一次运行结果，并回填已有运行日志。"

  def up do
    execute("ALTER TABLE sys_job ADD COLUMN IF NOT EXISTS last_status varchar(16)")

    execute(
      "ALTER TABLE sys_job ADD COLUMN IF NOT EXISTS last_run_at timestamp(6) without time zone"
    )

    execute("""
    WITH latest_runs AS (
      SELECT DISTINCT ON (job_id)
        job_id,
        CASE status
          WHEN 0 THEN 'FAILED'
          WHEN 1 THEN 'SUCCESS'
          WHEN 2 THEN 'SKIPPED'
          ELSE NULL
        END AS last_status,
        COALESCE(end_time, start_time) AS last_run_at
      FROM sys_job_log
      WHERE job_id IS NOT NULL
      ORDER BY job_id, COALESCE(end_time, start_time) DESC, job_log_id DESC
    )
    UPDATE sys_job AS job
    SET last_status = latest_runs.last_status,
        last_run_at = latest_runs.last_run_at
    FROM latest_runs
    WHERE job.job_id = latest_runs.job_id
      AND (job.last_run_at IS NULL OR job.last_run_at <= latest_runs.last_run_at)
    """)
  end

  def down do
    execute("ALTER TABLE sys_job DROP COLUMN IF EXISTS last_run_at")
    execute("ALTER TABLE sys_job DROP COLUMN IF EXISTS last_status")
  end
end
