defmodule KeystonePhoenix.Auth.AuthSession do
  @moduledoc "PostgreSQL-backed refresh session state shared by access and refresh tokens."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "auth_sessions" do
    field :user_id, :binary_id
    field :client_id, :string
    field :approved_scope, :string
    field :jti, :binary_id
    field :access_token_id, :binary_id
    field :refresh_family_id, :binary_id
    field :refresh_expires_at, :utc_datetime_usec
    field :idle_expires_at, :utc_datetime_usec
    field :last_seen_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :active, :boolean, default: true
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [
      :id,
      :user_id,
      :client_id,
      :approved_scope,
      :jti,
      :access_token_id,
      :refresh_family_id,
      :refresh_expires_at,
      :idle_expires_at,
      :last_seen_at,
      :expires_at,
      :active,
      :revoked_at
    ])
    |> validate_required([
      :user_id,
      :client_id,
      :jti,
      :access_token_id,
      :refresh_family_id,
      :refresh_expires_at
    ])
    |> validate_length(:client_id, max: 128)
    |> unique_constraint(:jti, name: :auth_sessions_jti_unique_index)
    |> unique_constraint(:access_token_id, name: :auth_sessions_access_token_id_unique_index)
  end
end
