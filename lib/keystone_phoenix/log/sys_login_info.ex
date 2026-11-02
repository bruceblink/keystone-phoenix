defmodule KeystonePhoenix.Log.SysLoginInfo do
  @moduledoc "PostgreSQL schema for a login audit record."

  use Ecto.Schema

  @primary_key {:info_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_login_info" do
    field :username, :string
    field :ip_address, :string
    field :login_location, :string
    field :browser, :string
    field :operation_system, :string
    field :status, :integer
    field :msg, :string
    field :login_time, :utc_datetime_usec
    field :deleted, :boolean, default: false
  end
end
