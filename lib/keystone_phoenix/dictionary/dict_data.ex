defmodule KeystonePhoenix.Dictionary.DictData do
  @moduledoc "PostgreSQL schema for a Keystone dictionary item."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dict_code, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_dict_data" do
    field :dict_type, :string
    field :dict_label, :string
    field :dict_value, :integer
    field :dict_sort, :integer, default: 0
    field :is_default, :boolean, default: false
    field :css_class, :string
    field :list_class, :string
    field :status, :integer, default: 1
    field :remark, :string
    field :creator_id, :integer
    field :updater_id, :integer
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(dict_data, attrs) do
    dict_data
    |> cast(attrs, [
      :dict_type,
      :dict_label,
      :dict_value,
      :dict_sort,
      :is_default,
      :css_class,
      :list_class,
      :status,
      :remark
    ])
    |> validate_required([:dict_type, :dict_label, :dict_value, :status])
    |> validate_length(:dict_type, max: 100)
    |> validate_length(:dict_label, max: 100)
    |> validate_length(:css_class, max: 100)
    |> validate_length(:list_class, max: 100)
    |> validate_length(:remark, max: 500)
    |> validate_inclusion(:status, [0, 1])
  end
end
