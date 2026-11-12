defmodule KeystonePhoenix.Authz.SysPermission do
  @moduledoc "PostgreSQL schema for a normalized authorization permission."

  use Ecto.Schema

  @primary_key {:permission_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_permission" do
    field :permission, :string
    field :resource, :string
    field :domain, :string
    field :action, :string
    field :description, :string, default: ""
    field :risk, :string, default: "low"
    field :deprecated, :boolean, default: false
    field :status, :integer, default: 1

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end
end
