defmodule KeystonePhoenix.Dictionary.DictData do
  @moduledoc "PostgreSQL schema for a Keystone dictionary item."

  use Ecto.Schema

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
end
