defmodule KeystonePhoenix.Repo.Migrations.AddRuntimeQueryIndexes do
  use Ecto.Migration

  def change do
    create index(:auth_sessions, [:active, :revoked_at, :expires_at],
             name: :auth_sessions_active_expiry_index
           )

    create index(:sys_user, [:deleted, :role_id], name: :sys_user_deleted_role_index)
    create index(:sys_notice, [:deleted, :notice_id], name: :sys_notice_deleted_id_index)

    create index(:sys_login_info, [:deleted, :login_time],
             name: :sys_login_info_deleted_time_index
           )

    create index(:sys_operation_log, [:deleted, :operation_time],
             name: :sys_operation_log_deleted_time_index
           )
  end
end
