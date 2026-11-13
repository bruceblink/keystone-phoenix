defmodule KeystonePhoenix.Department.SysDept do
  @moduledoc "PostgreSQL schema for a Keystone department."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:dept_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_dept" do
    field :parent_id, :binary_id
    field :ancestors, :string, default: ""
    field :dept_name, :string, default: ""
    field :order_num, :integer, default: 0
    field :leader_id, :binary_id
    field :leader_name, :string
    field :phone, :string
    field :email, :string
    field :status, :integer, default: 1
    field :creator_id, :binary_id
    field :updater_id, :binary_id
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end

  def changeset(dept, attrs) do
    dept
    |> cast(attrs, [
      :parent_id,
      :ancestors,
      :dept_name,
      :order_num,
      :leader_id,
      :leader_name,
      :phone,
      :email,
      :status
    ])
    |> put_new_id()
    |> validate_required([:dept_name, :status])
    |> validate_length(:dept_name, max: 64)
    |> validate_length(:ancestors, max: 1024)
    |> validate_length(:leader_name, max: 64)
    |> validate_length(:phone, max: 16)
    |> validate_length(:email, max: 128)
    |> validate_inclusion(:status, [0, 1])
  end

  # 新部门 ID 使用 UUIDv7，根部门的 parent_id 保持 NULL。
  defp put_new_id(changeset) do
    if Ecto.Changeset.get_field(changeset, :dept_id),
      do: changeset,
      else: Ecto.Changeset.put_change(changeset, :dept_id, KeystonePhoenix.Identity.v7())
  end
end
