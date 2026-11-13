defmodule KeystonePhoenix.Auth.RefreshToken do
  @moduledoc "Persistent refresh token rotation state."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "auth_refresh_tokens" do
    field :session_id, :binary_id
    field :user_id, :binary_id
    field :refresh_family_id, :binary_id
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec
    field :idle_expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :reused_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :id,
      :session_id,
      :user_id,
      :refresh_family_id,
      :token_hash,
      :expires_at,
      :idle_expires_at,
      :revoked_at,
      :reused_at
    ])
    |> validate_required([
      :id,
      :session_id,
      :user_id,
      :refresh_family_id,
      :token_hash,
      :expires_at,
      :idle_expires_at
    ])
    |> unique_constraint(:token_hash, name: :auth_refresh_tokens_hash_unique_index)
  end
end
