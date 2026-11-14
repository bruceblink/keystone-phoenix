defmodule KeystonePhoenix.Repo.Migrations.AddAccessTokenIdToAuthSessions do
  use Ecto.Migration

  @moduledoc "为会话保存当前 access token 标识，使 step-up 可以立即失效旧访问令牌。"

  def up do
    alter table(:auth_sessions) do
      add :access_token_id, :uuid
    end

    # 已存在的会话无法恢复旧 access jti；使用当前 refresh jti 作为一次性迁移值，
    # 使旧访问令牌在迁移后重新登录，且不保留不可核验的状态。
    execute("UPDATE auth_sessions SET access_token_id = jti WHERE access_token_id IS NULL")

    alter table(:auth_sessions) do
      modify :access_token_id, :uuid, null: false
    end

    create unique_index(:auth_sessions, [:access_token_id],
             name: :auth_sessions_access_token_id_unique_index
           )
  end

  def down do
    drop_if_exists unique_index(:auth_sessions, [:access_token_id],
                     name: :auth_sessions_access_token_id_unique_index
                   )

    alter table(:auth_sessions) do
      remove :access_token_id
    end
  end
end
