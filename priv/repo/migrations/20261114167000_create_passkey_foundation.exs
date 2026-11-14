defmodule KeystonePhoenix.Repo.Migrations.CreatePasskeyFoundation do
  use Ecto.Migration

  @moduledoc "创建 WebAuthn 账户、凭据和一次性挑战存储。"

  def up do
    create table(:auth_passkey_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id, references(:sys_user, column: :user_id, type: :uuid, on_delete: :delete_all),
        null: false

      add :username, :string, size: 64, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:auth_passkey_accounts, [:user_id],
             name: :auth_passkey_accounts_user_id_unique
           )

    Ithibati.Migration.up(version: 5)
  end

  def down do
    Ithibati.Migration.down(version: 5)
    drop_if_exists table(:auth_passkey_accounts)
  end
end
