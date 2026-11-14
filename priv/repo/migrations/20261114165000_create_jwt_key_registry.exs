defmodule KeystonePhoenix.Repo.Migrations.CreateJwtKeyRegistry do
  use Ecto.Migration

  @moduledoc "创建 JWT 公钥注册表，保存轮换状态和过期时间。"

  def up do
    create_if_not_exists table(:auth_jwt_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key_id, :string, size: 128, null: false
      add :public_jwk, :map, null: false
      add :status, :string, size: 16, null: false, default: "active"
      add :activated_at, :utc_datetime_usec, null: false
      add :retire_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(:auth_jwt_keys, [:key_id],
                           name: :auth_jwt_keys_key_id_unique
                         )

    create_if_not_exists index(:auth_jwt_keys, [:status, :expires_at],
                           name: :auth_jwt_keys_state_index
                         )

    ensure_constraint(
      "auth_jwt_keys",
      "auth_jwt_keys_status_check",
      "status in ('active', 'retiring', 'retired')"
    )

    ensure_constraint(
      "auth_jwt_keys",
      "auth_jwt_keys_key_id_check",
      "key_id ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'"
    )
  end

  def down do
    drop_if_exists(table(:auth_jwt_keys))
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
