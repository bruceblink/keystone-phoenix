defmodule KeystonePhoenix.Repo.Migrations.RebuildAuthSessionState do
  use Ecto.Migration

  @moduledoc "重建认证会话、刷新令牌和刷新事件表，使状态模型与 Native 对齐。"

  def up do
    # clean-break 允许删除旧会话；访问令牌和刷新令牌必须在部署切换时重新签发。
    execute("DROP TABLE IF EXISTS auth_refresh_token_events CASCADE")
    execute("DROP TABLE IF EXISTS auth_refresh_tokens CASCADE")
    execute("DROP TABLE IF EXISTS auth_sessions CASCADE")

    create table(:auth_sessions, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :user_id, references(:sys_user, column: :user_id, type: :uuid, on_delete: :delete_all),
        null: false

      add :client_id, :string, size: 128, null: false
      add :approved_scope, :text
      add :jti, :uuid, null: false
      add :refresh_family_id, :uuid, null: false
      add :refresh_expires_at, :utc_datetime_usec, null: false
      add :idle_expires_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :active, :boolean, null: false, default: true
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:auth_sessions, [:jti], name: :auth_sessions_jti_unique_index)

    create index(:auth_sessions, [:user_id, :active, :revoked_at],
             name: :auth_sessions_user_state_index
           )

    create index(:auth_sessions, [:refresh_family_id], name: :auth_sessions_family_index)

    create index(:auth_sessions, [:refresh_expires_at, :idle_expires_at],
             name: :auth_sessions_expiry_index
           )

    create unique_index(:auth_sessions, [:user_id],
             name: :auth_sessions_active_user_unique_index,
             where: "active = true AND revoked_at IS NULL"
           )

    create table(:auth_refresh_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :session_id,
          references(:auth_sessions, column: :id, type: :uuid, on_delete: :delete_all),
          null: false

      add :user_id, references(:sys_user, column: :user_id, type: :uuid, on_delete: :delete_all),
        null: false

      add :refresh_family_id, :uuid, null: false
      add :token_hash, :string, size: 64, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :idle_expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec
      add :reused_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:auth_refresh_tokens, [:token_hash],
             name: :auth_refresh_tokens_hash_unique_index
           )

    create index(:auth_refresh_tokens, [:session_id, :revoked_at],
             name: :auth_refresh_tokens_session_state_index
           )

    create index(:auth_refresh_tokens, [:refresh_family_id, :revoked_at],
             name: :auth_refresh_tokens_family_state_index
           )

    create table(:auth_refresh_token_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :token_id,
          references(:auth_refresh_tokens, column: :id, type: :uuid, on_delete: :nilify_all)

      add :user_id, references(:sys_user, column: :user_id, type: :uuid, on_delete: :nilify_all)
      add :refresh_family_id, :uuid, null: false
      add :event_type, :string, size: 32, null: false
      add :client_id, :string, size: 128
      add :detail, :string, size: 255

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:auth_refresh_token_events, [:refresh_family_id, :inserted_at],
             name: :auth_refresh_token_events_family_time_index
           )
  end

  def down do
    # 旧整数会话结构不可逆恢复；回滚边界是应用版本和数据库备份。
    :ok
  end
end
