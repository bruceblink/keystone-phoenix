defmodule KeystonePhoenix.Repo.Migrations.CreateLogTables do
  use Ecto.Migration

  def change do
    create table(:sys_login_info, primary_key: false) do
      add :info_id, :bigserial, primary_key: true
      add :username, :string, size: 50, null: false, default: ""
      add :ip_address, :string, size: 128, null: false, default: ""
      add :login_location, :string, size: 255, null: false, default: ""
      add :browser, :string, size: 50, null: false, default: ""
      add :operation_system, :string, size: 50, null: false, default: ""
      add :status, :smallint, null: false, default: 0
      add :msg, :string, size: 255, null: false, default: ""
      add :login_time, :utc_datetime_usec
      add :deleted, :boolean, null: false, default: false
    end

    create index(:sys_login_info, [:username], name: :sys_login_info_username_index)
    create index(:sys_login_info, [:status], name: :sys_login_info_status_index)

    create table(:sys_operation_log, primary_key: false) do
      add :operation_id, :bigserial, primary_key: true
      add :business_type, :smallint, null: false, default: 0
      add :request_method, :smallint, null: false, default: 0
      add :request_module, :string, size: 64, null: false, default: ""
      add :request_url, :string, size: 256, null: false, default: ""
      add :called_method, :string, size: 128, null: false, default: ""
      add :operator_type, :smallint, null: false, default: 1
      add :user_id, :bigint, default: 0
      add :username, :string, size: 32, default: ""
      add :operator_ip, :string, size: 128, default: ""
      add :operator_location, :string, size: 256
      add :dept_id, :bigint, default: 0
      add :dept_name, :string, size: 64
      add :operation_param, :string, size: 2048, default: ""
      add :operation_result, :string, size: 2048, default: ""
      add :status, :smallint, null: false, default: 1
      add :error_stack, :string, size: 2048, default: ""
      add :operation_time, :utc_datetime_usec, null: false
      add :deleted, :boolean, null: false, default: false
    end

    create index(:sys_operation_log, [:user_id], name: :sys_operation_log_user_id_index)

    create index(:sys_operation_log, [:operation_time],
             name: :sys_operation_log_operation_time_index
           )
  end
end
