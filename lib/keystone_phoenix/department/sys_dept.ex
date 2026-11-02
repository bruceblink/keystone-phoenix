defmodule KeystonePhoenix.Department.SysDept do
  @moduledoc "PostgreSQL schema for a Keystone department."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dept_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_dept" do
    field :parent_id, :integer, default: 0
    field :ancestors, :string, default: "0"
    field :dept_name, :string, default: ""
    field :order_num, :integer, default: 0
    field :leader_id, :integer
    field :leader_name, :string
    field :phone, :string
    field :email, :string
    field :status, :integer, default: 1
    field :creator_id, :integer
    field :updater_id, :integer
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(dept, attrs) do
    dept
    |> cast(attrs, [:parent_id, :ancestors, :dept_name, :order_num, :leader_id, :leader_name, :phone, :email, :status])
    |> validate_required([:dept_name, :status])
    |> validate_length(:dept_name, max: 64)
    |> validate_length(:ancestors, max: 1024)
    |> validate_length(:leader_name, max: 64)
    |> validate_length(:phone, max: 16)
    |> validate_length(:email, max: 128)
    |> validate_inclusion(:status, [0, 1])
  end
end
