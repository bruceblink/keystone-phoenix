defmodule KeystonePhoenix.Dictionary.DictType do
  @moduledoc "PostgreSQL schema for a Keystone dictionary type."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dict_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_dict_type" do
    field :dict_name, :string
    field :dict_type, :string
    field :status, :integer, default: 1
    field :remark, :string
    field :creator_id, :integer
    field :updater_id, :integer
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(dict_type, attrs) do
    dict_type
    |> cast(attrs, [:dict_name, :dict_type, :status, :remark])
    |> validate_required([:dict_name, :dict_type, :status])
    |> validate_length(:dict_name, max: 100)
    |> validate_length(:dict_type, max: 100)
    |> validate_length(:remark, max: 500)
    |> validate_inclusion(:status, [0, 1])
    |> unique_constraint(:dict_type, name: :sys_dict_type_dict_type_unique_index)
  end
end
