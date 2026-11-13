defmodule KeystonePhoenix.Auth.AuthSession do
  @moduledoc "PostgreSQL-backed refresh token session."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :id

  schema "auth_sessions" do
    field :jti, :string
    field :user_id, :binary_id
    field :expires_at, :utc_datetime_usec
    field :active, :boolean, default: true
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:jti, :user_id, :expires_at, :active, :revoked_at])
    |> validate_required([:jti, :user_id, :expires_at])
    |> validate_length(:jti, max: 128)
    |> unique_constraint(:jti, name: :auth_sessions_jti_unique_index)
  end
end
