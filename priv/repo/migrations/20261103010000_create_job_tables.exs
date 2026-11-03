defmodule KeystonePhoenix.Repo.Migrations.CreateJobTables do
  use Ecto.Migration

  def change do
    create table(:sys_job, primary_key: false) do
      add :job_id, :bigserial, primary_key: true
      add :job_name, :string, size: 64, null: false, default: ""
      add :job_group, :string, size: 64, null: false, default: ""
      add :invoke_target, :string, size: 255, null: false, default: ""
      add :job_params, :text
      add :cron_expression, :string, size: 255, null: false, default: ""
      add :concurrent, :smallint, null: false, default: 0
      add :status, :smallint, null: false, default: 0
      add :remark, :string, size: 500
      add :creator_id, :bigint
      add :updater_id, :bigint

      timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
    end

    create index(:sys_job, [:job_group], name: :sys_job_group_index)
    create index(:sys_job, [:status], name: :sys_job_status_index)

    create table(:sys_job_log, primary_key: false) do
      add :job_log_id, :bigserial, primary_key: true
      add :job_id, :bigint
      add :job_name, :string, size: 64, null: false, default: ""
      add :job_group, :string, size: 64, null: false, default: ""
      add :invoke_target, :string, size: 255, null: false, default: ""
      add :job_params, :text
      add :cron_expression, :string, size: 255
      add :trigger_type, :smallint, null: false, default: 1
      add :status, :smallint, null: false, default: 1
      add :job_message, :string, size: 500
      add :exception_info, :string, size: 2000
      add :start_time, :utc_datetime_usec, null: false
      add :end_time, :utc_datetime_usec
      add :duration_ms, :bigint
      add :create_time, :utc_datetime_usec, null: false, default: fragment("CURRENT_TIMESTAMP")
    end

    create index(:sys_job_log, [:job_id], name: :sys_job_log_job_id_index)
    create index(:sys_job_log, [:start_time], name: :sys_job_log_start_time_index)
    create index(:sys_job_log, [:status], name: :sys_job_log_status_index)
  end
end
