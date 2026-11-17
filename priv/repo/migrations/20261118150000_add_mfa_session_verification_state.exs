defmodule KeystonePhoenix.Repo.Migrations.AddMfaSessionVerificationState do
  use Ecto.Migration

  # 保存当前会话最近一次 TOTP 或恢复码认证结果，供敏感操作按 600 秒窗口核验。
  def change do
    alter table(:auth_sessions) do
      add_if_not_exists :mfa_verified_at, :utc_datetime_usec
      add_if_not_exists :mfa_assurance, :string, size: 32
      add_if_not_exists :mfa_amr, :string, size: 32
    end
  end
end
