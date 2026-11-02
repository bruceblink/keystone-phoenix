defmodule KeystonePhoenix.Log.SysOperationLog do
  @moduledoc "PostgreSQL schema for an operation audit record."

  use Ecto.Schema

  @primary_key {:operation_id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "sys_operation_log" do
    field :business_type, :integer
    field :request_method, :integer
    field :request_module, :string
    field :request_url, :string
    field :called_method, :string
    field :operator_type, :integer
    field :user_id, :integer
    field :username, :string
    field :operator_ip, :string
    field :operator_location, :string
    field :dept_id, :integer
    field :dept_name, :string
    field :operation_param, :string
    field :operation_result, :string
    field :status, :integer
    field :error_stack, :string
    field :operation_time, :utc_datetime_usec
    field :deleted, :boolean, default: false
  end
end
