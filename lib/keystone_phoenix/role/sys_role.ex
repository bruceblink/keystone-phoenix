defmodule KeystonePhoenix.Role.SysRole do
  @moduledoc "PostgreSQL schema for a Keystone role."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:role_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_role" do
    field :role_name, :string
    field :role_key, :string
    field :role_sort, :integer, default: 0
    field :data_scope, :integer, default: 1
    field :dept_id_set, :string, default: ""
    field :status, :integer, default: 1
    field :creator_id, :integer
    field :updater_id, :integer
    field :remark, :string
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(role, attrs) do
    role
    |> cast(attrs, [
      :role_name,
      :role_key,
      :role_sort,
      :data_scope,
      :dept_id_set,
      :status,
      :remark
    ])
    |> validate_required([:role_name, :role_key, :role_sort, :status])
    |> validate_length(:role_name, max: 32)
    |> validate_length(:role_key, max: 128)
    |> validate_length(:dept_id_set, max: 1024)
    |> validate_length(:remark, max: 512)
    |> validate_inclusion(:data_scope, [1, 2, 3, 4, 5])
    |> validate_inclusion(:status, [0, 1])
    |> unique_constraint(:role_key, name: :sys_role_role_key_unique_index)
  end
end
