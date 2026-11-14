defmodule KeystonePhoenix.Auth.Oidc.AuthorizationCodeRecord do
  @moduledoc "PostgreSQL 中保存 OIDC provider 一次性授权码的记录。"

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "auth_oidc_authorization_codes" do
    field :code_hash, :binary
    field :provider, :string
    field :client_id, :string
    field :redirect_uri, :string
    field :state_hash, :binary
    field :created_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :consumed_at, :utc_datetime_usec
  end
end
