defmodule KeystonePhoenix.Auth.ApiKey.Key do
  @moduledoc "PostgreSQL schema for an API Key; only a SHA-256 digest is persisted."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_api_key" do
    field :user_id, :binary_id
    field :subject_id, :binary_id
    field :created_by, :binary_id
    field :name, :string
    field :key_prefix, :string
    field :key_hash, :string
    field :scopes, :string
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime_usec
    field :last_used_ip, :string
    field :rotated_to, :binary_id
    field :revoked_reason, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc "校验 API Key 持久化字段，禁止明文凭据进入 schema。"
  def changeset(key, attrs) do
    key
    |> cast(attrs, [
      :id,
      :user_id,
      :subject_id,
      :created_by,
      :name,
      :key_prefix,
      :key_hash,
      :scopes,
      :expires_at,
      :revoked_at,
      :last_used_at,
      :last_used_ip,
      :rotated_to,
      :revoked_reason
    ])
    |> validate_required([:id, :user_id, :subject_id, :name, :key_prefix, :key_hash, :scopes])
    |> validate_length(:name, max: 128)
    |> validate_format(:key_prefix, ~r/\A[A-Za-z0-9_-]{8,24}\z/)
    |> validate_format(:key_hash, ~r/\A[0-9a-f]{64}\z/)
    |> validate_length(:scopes, max: 4096)
    |> validate_length(:last_used_ip, max: 64)
    |> validate_length(:revoked_reason, max: 255)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:subject_id)
    |> foreign_key_constraint(:created_by)
    |> unique_constraint(:key_prefix, name: :sys_api_key_prefix_unique_index)
    |> unique_constraint(:key_hash, name: :sys_api_key_hash_unique_index)
  end
end
