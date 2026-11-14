defmodule KeystonePhoenix.Repo.Migrations.CreateOidcAuthorizationCodes do
  use Ecto.Migration

  @moduledoc "创建 OIDC 外部授权码的一次性消费记录。"

  def change do
    create table(:auth_oidc_authorization_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code_hash, :binary, null: false
      add :provider, :string, size: 64, null: false
      add :client_id, :string, size: 128, null: false
      add :redirect_uri, :string, size: 512, null: false
      add :state_hash, :binary, null: false
      add :created_at, :utc_datetime_usec, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
    end

    create unique_index(:auth_oidc_authorization_codes, [:code_hash],
             name: :auth_oidc_authorization_codes_code_hash_unique
           )

    create index(:auth_oidc_authorization_codes, [:expires_at],
             name: :auth_oidc_authorization_codes_expiry_index
           )
  end
end
