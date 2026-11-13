defmodule KeystonePhoenix.Dictionary.DictType do
  @moduledoc "PostgreSQL schema for a Keystone dictionary type."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dict_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_dict_type" do
    field :dict_name, :string
    field :dict_type, :string
    field :status, :integer, default: 1
    field :remark, :string
    field :creator_id, :binary_id
    field :updater_id, :binary_id
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(dict_type, attrs) do
    dict_type
    |> cast(attrs, [:dict_name, :dict_type, :status, :remark])
    |> put_new_id()
    |> validate_required([:dict_name, :dict_type, :status])
    |> validate_length(:dict_name, max: 100)
    |> validate_length(:dict_type, max: 100)
    |> validate_length(:remark, max: 500)
    |> validate_inclusion(:status, [0, 1])
    |> unique_constraint(:dict_type, name: :sys_dict_type_dict_type_unique_index)
  end

  # 新字典类型 ID 使用 UUIDv7。
  defp put_new_id(changeset) do
    if get_field(changeset, :dict_id),
      do: changeset,
      else: put_change(changeset, :dict_id, KeystonePhoenix.Identity.v7())
  end
end
