defmodule KeystonePhoenix.Notice.SysNotice do
  @moduledoc "PostgreSQL schema for a Keystone notice."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:notice_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_notice" do
    field :notice_title, :string
    field :notice_type, :integer
    field :notice_content, :string
    field :status, :integer, default: 1
    field :creator_id, :binary_id
    field :updater_id, :binary_id
    field :remark, :string, default: ""
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(notice, attrs) do
    notice
    |> cast(attrs, [:notice_title, :notice_type, :notice_content, :status, :remark])
    |> put_new_id()
    |> validate_required([:notice_title, :notice_type, :notice_content, :status])
    |> validate_length(:notice_title, max: 64)
    |> validate_length(:notice_content, max: 100_000)
    |> validate_length(:remark, max: 255)
    |> validate_inclusion(:notice_type, [1, 2])
    |> validate_inclusion(:status, [0, 1])
  end

  # 新公告 ID 使用 UUIDv7；操作者 ID 由统一用户主键传入。
  defp put_new_id(changeset) do
    if get_field(changeset, :notice_id),
      do: changeset,
      else: put_change(changeset, :notice_id, KeystonePhoenix.Identity.v7())
  end
end
