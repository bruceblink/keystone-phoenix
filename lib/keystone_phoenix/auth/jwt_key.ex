defmodule KeystonePhoenix.Auth.JwtKey do
  @moduledoc "PostgreSQL schema for a registered JWT public key and its lifecycle state."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "auth_jwt_keys" do
    field :key_id, :string
    field :public_jwk, :map
    field :status, :string, default: "active"
    field :activated_at, :utc_datetime_usec
    field :retire_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end

  def changeset(key, attrs) do
    key
    |> cast(attrs, [:id, :key_id, :public_jwk, :status, :activated_at, :retire_at, :expires_at])
    |> validate_required([:id, :key_id, :public_jwk, :status, :activated_at])
    |> validate_format(:key_id, ~r/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/)
    |> validate_inclusion(:status, ["active", "retiring", "retired"])
    |> validate_change(:public_jwk, fn :public_jwk, value ->
      if is_map(value) and value["kty"] == "RSA" and is_binary(value["n"]) and
           is_binary(value["e"]),
         do: [],
         else: [public_jwk: "必须是完整的 RSA 公钥 JWK"]
    end)
    |> unique_constraint(:key_id, name: :auth_jwt_keys_key_id_unique)
  end
end
