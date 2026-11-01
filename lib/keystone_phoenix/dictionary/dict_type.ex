defmodule KeystonePhoenix.Dictionary.DictType do
  @moduledoc "PostgreSQL schema for a Keystone dictionary type."

  use Ecto.Schema

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
end
