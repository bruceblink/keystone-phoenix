defmodule KeystonePhoenix.Repo.Migrations.CreateAuthSessions do
  use Ecto.Migration

  def change do
    create table(:auth_sessions) do
      add :jti, :string, size: 128, null: false
      add :user_id, references(:sys_user, column: :user_id, type: :bigint), null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :active, :boolean, null: false, default: true
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:auth_sessions, [:jti], name: :auth_sessions_jti_unique_index)
    create index(:auth_sessions, [:user_id, :expires_at], name: :auth_sessions_user_expiry_index)
    create index(:auth_sessions, [:expires_at], name: :auth_sessions_expiry_index)

    create unique_index(:auth_sessions, [:user_id],
             name: :auth_sessions_active_user_unique_index,
             where: "active = true AND revoked_at IS NULL"
           )
  end
end
