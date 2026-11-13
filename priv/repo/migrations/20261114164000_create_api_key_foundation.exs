defmodule KeystonePhoenix.Repo.Migrations.CreateApiKeyFoundation do
  use Ecto.Migration

  @moduledoc "创建服务主体、API Key 和失败限流状态。"

  def up do
    create_subject_table()
    create_api_key_table()
    create_rate_limit_table()
  end

  def down do
    drop_if_exists(table(:sys_api_key_rate_limit))
    drop_if_exists(table(:sys_api_key))
    drop_if_exists(table(:sys_service_subject))
  end

  defp create_subject_table do
    create_if_not_exists table(:sys_service_subject, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, size: 128, null: false
      add :name, :string, size: 128, null: false

      add :owner_user_id,
          references(:sys_user, column: :user_id, type: :binary_id, on_delete: :nilify_all)

      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:sys_service_subject, [:code],
                           name: :sys_service_subject_code_unique_index
                         )

    create_if_not_exists index(:sys_service_subject, [:owner_user_id, :enabled],
                           name: :sys_service_subject_owner_index
                         )

    ensure_constraint(
      "sys_service_subject",
      "sys_service_subject_code_check",
      "code ~ '^user:[0-9a-f-]{36}$'"
    )
  end

  defp create_api_key_table do
    create_if_not_exists table(:sys_api_key, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:sys_user, column: :user_id, type: :binary_id, on_delete: :delete_all),
          null: false

      # 主体禁用或删除后保留 API Key 元数据，但认证必须因主体为空而拒绝。
      add :subject_id,
          references(:sys_service_subject, column: :id, type: :binary_id, on_delete: :nilify_all)

      add :created_by,
          references(:sys_user, column: :user_id, type: :binary_id, on_delete: :nilify_all)

      add :name, :string, size: 128, null: false
      add :key_prefix, :string, size: 24, null: false
      add :key_hash, :string, size: 64, null: false
      add :scopes, :text, null: false
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :last_used_at, :utc_datetime_usec
      add :last_used_ip, :string, size: 64
      add :rotated_to, :binary_id
      add :revoked_reason, :string, size: 255

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:sys_api_key, [:key_prefix],
                           name: :sys_api_key_prefix_unique_index
                         )

    create_if_not_exists unique_index(:sys_api_key, [:key_hash],
                           name: :sys_api_key_hash_unique_index
                         )

    create_if_not_exists index(:sys_api_key, [:user_id, :revoked_at, :expires_at],
                           name: :sys_api_key_user_state_index
                         )

    create_if_not_exists index(:sys_api_key, [:subject_id, :revoked_at, :expires_at],
                           name: :sys_api_key_subject_state_index
                         )

    ensure_constraint(
      "sys_api_key",
      "sys_api_key_prefix_check",
      "key_prefix ~ '^[A-Za-z0-9_-]{8,24}$'"
    )

    ensure_constraint("sys_api_key", "sys_api_key_hash_check", "key_hash ~ '^[0-9a-f]{64}$'")
  end

  defp create_rate_limit_table do
    create_if_not_exists table(:sys_api_key_rate_limit, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scope_key, :string, size: 64, null: false
      add :window_started_at, :utc_datetime_usec, null: false
      add :attempt_count, :integer, null: false, default: 0
      add :blocked_until, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:sys_api_key_rate_limit, [:scope_key],
                           name: :sys_api_key_rate_limit_scope_key_unique_index
                         )

    ensure_constraint(
      "sys_api_key_rate_limit",
      "sys_api_key_rate_limit_attempt_check",
      "attempt_count >= 0"
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
