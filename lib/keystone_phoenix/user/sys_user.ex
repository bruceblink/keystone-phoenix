defmodule KeystonePhoenix.User.SysUser do
  @moduledoc "PostgreSQL schema for a Keystone system user."

  use Ecto.Schema

  @primary_key {:user_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_user" do
    field :post_id, :integer
    field :role_id, :integer
    field :dept_id, :integer
    field :username, :string
    field :nickname, :string
    field :user_type, :integer, default: 0
    field :email, :string, default: ""
    field :phone_number, :string, default: ""
    field :sex, :integer, default: 2
    field :avatar, :string, default: ""
    field :password, :string
    field :status, :integer, default: 1
    field :login_ip, :string, default: ""
    field :login_date, :utc_datetime_usec
    field :is_admin, :boolean, default: false
    field :external_subject, :string
    field :external_user_id, :string
    field :creator_id, :integer
    field :updater_id, :integer
    field :remark, :string
    field :deleted, :boolean, default: false

    timestamps(inserted_at: :create_time, updated_at: :update_time, type: :utc_datetime_usec)
  end
end
