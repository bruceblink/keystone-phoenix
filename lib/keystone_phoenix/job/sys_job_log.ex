defmodule KeystonePhoenix.Job.SysJobLog do
  @moduledoc "PostgreSQL schema for a scheduled job execution log."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:job_log_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_job_log" do
    field :job_id, :binary_id
    field :job_name, :string
    field :job_group, :string
    field :invoke_target, :string
    field :job_params, :string
    field :cron_expression, :string
    field :trigger_type, :integer, default: 1
    field :status, :integer, default: 1
    field :job_message, :string
    field :exception_info, :string
    field :start_time, :utc_datetime_usec
    field :end_time, :utc_datetime_usec
    field :duration_ms, :integer
    field :create_time, :utc_datetime_usec
  end

  @fields [
    :job_id,
    :job_name,
    :job_group,
    :invoke_target,
    :job_params,
    :cron_expression,
    :trigger_type,
    :status,
    :job_message,
    :exception_info,
    :start_time,
    :end_time,
    :duration_ms,
    :create_time
  ]

  def changeset(log, attrs) do
    log
    |> cast(attrs, @fields)
    |> put_new_id()
    |> validate_required([
      :job_name,
      :job_group,
      :invoke_target,
      :trigger_type,
      :status,
      :start_time
    ])
    |> validate_length(:job_name, max: 64)
    |> validate_length(:job_group, max: 64)
    |> validate_length(:invoke_target, max: 255)
    |> validate_length(:job_message, max: 500)
    |> validate_length(:exception_info, max: 2000)
    |> validate_inclusion(:trigger_type, [1, 2])
    |> validate_inclusion(:status, [0, 1, 2])
  end

  # 每条执行日志使用独立 UUIDv7，job_id 引用任务 UUID。
  defp put_new_id(changeset) do
    if get_field(changeset, :job_log_id),
      do: changeset,
      else: put_change(changeset, :job_log_id, KeystonePhoenix.Identity.v7())
  end
end
