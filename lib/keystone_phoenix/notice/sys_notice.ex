defmodule KeystonePhoenix.Notice.SysNotice do
  @moduledoc "PostgreSQL schema for a Keystone notice."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:notice_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_notice" do
    field :notice_title, :string
    field :notice_type, :string, default: "NOTICE"
    field :notice_content, :string
    field :status, :integer, default: 1
    field :published, :boolean, default: false
    field :publish_at, :utc_datetime_usec
    field :creator_id, :binary_id
    field :owner_id, :binary_id
    field :updater_id, :binary_id
    field :remark, :string, default: ""
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(notice, attrs) do
    notice
    |> cast(attrs, [:notice_title, :notice_type, :notice_content, :status, :remark])
    |> put_exact_notice_type(attrs)
    |> put_new_id()
    |> validate_required([:notice_title, :notice_content, :status])
    |> validate_length(:notice_title, max: 64)
    |> validate_length(:notice_content, max: 100_000)
    |> validate_notice_type_length()
    |> validate_length(:remark, max: 255)
    |> validate_inclusion(:status, [0, 1])
  end

  # 保留 Native 接受的空字符串和纯空白字符串，其他字段仍沿用 Ecto 默认空值规则。
  defp put_exact_notice_type(changeset, attrs) do
    case Map.get(attrs, :notice_type) do
      value when is_binary(value) -> put_change(changeset, :notice_type, value)
      _value -> changeset
    end
  end

  # PostgreSQL varchar(32) 按 Unicode 码点计数，Ecto 的通用长度校验按字素簇计数。
  defp validate_notice_type_length(changeset) do
    validate_change(changeset, :notice_type, fn :notice_type, value ->
      if length(String.codepoints(value)) > 32,
        do: [notice_type: {"should be at most 32 characters", []}],
        else: []
    end)
  end

  # 新公告 ID 使用 UUIDv7；操作者 ID 由统一用户主键传入。
  defp put_new_id(changeset) do
    if get_field(changeset, :notice_id),
      do: changeset,
      else: put_change(changeset, :notice_id, KeystonePhoenix.Identity.v7())
  end
end
