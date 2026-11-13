defmodule KeystonePhoenix.Repo.Migrations.CreateMfaFoundation do
  use Ecto.Migration

  @moduledoc "创建跨项目统一的 MFA、认证请求和失败限流状态。"

  def up do
    add_user_policy_columns()
    create_factor_table()
    create_recovery_table()
    create_challenge_table()
    create_rate_limit_table()
  end

  def down do
    drop_if_exists(table(:sys_mfa_rate_limit))
    drop_if_exists(table(:sys_auth_challenge))
    drop_if_exists(table(:sys_mfa_recovery_code))
    drop_if_exists(table(:sys_user_mfa))
    drop_user_policy_columns()
  end

  defp add_user_policy_columns do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = 'sys_user' AND column_name = 'mfa_required'
      ) THEN
        ALTER TABLE sys_user ADD COLUMN mfa_required boolean NOT NULL DEFAULT false;
      END IF;
      IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = 'sys_user' AND column_name = 'mfa_grace_until'
      ) THEN
        ALTER TABLE sys_user ADD COLUMN mfa_grace_until timestamptz;
      END IF;
    END $$;
    """)
  end

  defp drop_user_policy_columns do
    execute("ALTER TABLE sys_user DROP COLUMN IF EXISTS mfa_grace_until")
    execute("ALTER TABLE sys_user DROP COLUMN IF EXISTS mfa_required")
  end

  defp create_factor_table do
    create_if_not_exists table(:sys_user_mfa, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:sys_user, column: :user_id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :mfa_type, :string, size: 16, null: false, default: "TOTP"
      add :secret_ciphertext, :binary, null: false

      # PostgreSQL bytea 不支持类型长度修饰；领域 changeset 强制 nonce 为 12 字节。
      add :secret_nonce, :binary, null: false
      add :key_version, :integer, null: false, default: 1
      add :enabled, :boolean, null: false, default: false
      add :enrolled_at, :utc_datetime_usec
      add :last_used_at, :utc_datetime_usec
      add :failed_attempt_count, :integer, null: false, default: 0
      add :locked_until, :utc_datetime_usec
      add :last_accepted_step, :bigint

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:sys_user_mfa, [:user_id],
                           name: :sys_user_mfa_user_unique_index
                         )

    create_if_not_exists index(:sys_user_mfa, [:user_id, :enabled],
                           name: :sys_user_mfa_enabled_index
                         )

    create_if_not_exists index(:sys_user_mfa, [:locked_until], name: :sys_user_mfa_locked_index)
    ensure_constraint("sys_user_mfa", "sys_user_mfa_type_check", "mfa_type = 'TOTP'")
    ensure_constraint("sys_user_mfa", "sys_user_mfa_key_version_check", "key_version > 0")

    ensure_constraint(
      "sys_user_mfa",
      "sys_user_mfa_nonce_check",
      "octet_length(secret_nonce) = 12"
    )
  end

  defp create_recovery_table do
    create_if_not_exists table(:sys_mfa_recovery_code, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:sys_user, column: :user_id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :batch_id, :binary_id, null: false
      add :code_hash, :string, size: 64, null: false
      add :used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:sys_mfa_recovery_code, [:user_id, :code_hash],
                           name: :sys_mfa_recovery_user_hash_unique_index
                         )

    create_if_not_exists index(:sys_mfa_recovery_code, [:user_id, :batch_id],
                           name: :sys_mfa_recovery_batch_index
                         )

    create_if_not_exists index(:sys_mfa_recovery_code, [:user_id, :used_at],
                           name: :sys_mfa_recovery_active_index
                         )
  end

  defp create_challenge_table do
    create_if_not_exists table(:sys_auth_challenge, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:sys_user, column: :user_id, type: :binary_id, on_delete: :delete_all),
          null: false

      add :purpose, :string, size: 16, null: false
      add :client_id, :string, size: 128, null: false

      # session_id 的外键由认证会话迁移统一补充，避免领域迁移依赖未完成的 session 重构。
      add :session_id, :binary_id
      add :context_hash, :string, size: 64
      add :expires_at, :utc_datetime_usec, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :consumed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(
                           :sys_auth_challenge,
                           [:user_id, :purpose, :consumed_at, :expires_at],
                           name: :sys_auth_challenge_state_index
                         )

    create_if_not_exists index(:sys_auth_challenge, [:session_id, :purpose, :consumed_at],
                           name: :sys_auth_challenge_session_index
                         )

    ensure_constraint(
      "sys_auth_challenge",
      "sys_auth_challenge_purpose_check",
      "purpose IN ('LOGIN', 'STEP_UP', 'ENROLL', 'RECOVERY')"
    )
  end

  defp create_rate_limit_table do
    create_if_not_exists table(:sys_mfa_rate_limit, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scope_key, :string, size: 64, null: false
      add :window_started_at, :utc_datetime_usec, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :blocked_until, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:sys_mfa_rate_limit, [:scope_key],
                           name: :sys_mfa_rate_limit_scope_key_unique_index
                         )
  end

  defp ensure_constraint(table, name, check) do
    execute("""
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = '#{table}'::regclass AND conname = '#{name}'
      ) THEN
        ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{check});
      END IF;
    END $$;
    """)
  end
end
