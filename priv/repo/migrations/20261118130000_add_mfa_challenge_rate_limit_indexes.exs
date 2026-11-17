defmodule KeystonePhoenix.Repo.Migrations.AddMfaChallengeRateLimitIndexes do
  use Ecto.Migration

  # 为 STEP_UP 窗口计数和有界过期清理增加查询索引，不回写已执行的迁移。
  def change do
    create_if_not_exists index(:sys_auth_challenge, [:expires_at],
                           name: :sys_auth_challenge_expiry_index
                         )

    create_if_not_exists index(
                           :sys_auth_challenge,
                           [:user_id, :session_id, :purpose, :inserted_at],
                           name: :sys_auth_challenge_step_up_issue_index
                         )
  end
end
