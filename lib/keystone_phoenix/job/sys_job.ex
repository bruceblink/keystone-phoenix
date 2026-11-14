defmodule KeystonePhoenix.Job.SysJob do
  @moduledoc "PostgreSQL schema for a database-backed scheduled job."

  use Ecto.Schema
  import Ecto.Changeset

  alias KeystonePhoenix.Job.Cron

  @primary_key {:job_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_job" do
    field :job_name, :string
    field :job_group, :string
    field :invoke_target, :string
    field :job_params, :string
    field :cron_expression, :string
    field :concurrent, :integer, default: 0
    field :status, :integer, default: 0
    field :remark, :string
    field :creator_id, :binary_id
    field :created_by, :binary_id
    field :updater_id, :binary_id

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  @fields [
    :job_name,
    :job_group,
    :invoke_target,
    :job_params,
    :cron_expression,
    :concurrent,
    :status,
    :remark
  ]

  def changeset(job, attrs) do
    job
    |> cast(attrs, @fields)
    |> put_new_id()
    |> validate_required([
      :job_name,
      :job_group,
      :invoke_target,
      :cron_expression,
      :concurrent,
      :status
    ])
    |> validate_length(:job_name, max: 64)
    |> validate_length(:job_group, max: 64)
    |> validate_length(:invoke_target, max: 255)
    |> validate_length(:cron_expression, max: 255)
    |> validate_length(:remark, max: 500)
    |> validate_inclusion(:concurrent, [0, 1])
    |> validate_inclusion(:status, [0, 1])
    |> validate_cron()
    |> validate_params()
  end

  # 新任务 ID 使用 UUIDv7；固定系统任务由 seed 显式提供 UUIDv5。
  defp put_new_id(changeset) do
    if get_field(changeset, :job_id),
      do: changeset,
      else: put_change(changeset, :job_id, KeystonePhoenix.Identity.v7())
  end

  defp validate_cron(changeset) do
    validate_change(changeset, :cron_expression, fn :cron_expression, value ->
      case Cron.validate(value) do
        :ok -> []
        {:error, _reason} -> [cron_expression: "Cron表达式无效"]
      end
    end)
  end

  defp validate_params(changeset) do
    validate_change(changeset, :job_params, fn :job_params, value ->
      if is_nil(value) or String.trim(value) == "" do
        []
      else
        case Jason.decode(value) do
          {:ok, _decoded} -> []
          {:error, _reason} -> [job_params: "任务参数必须是有效JSON"]
        end
      end
    end)
  end
end
