defmodule KeystonePhoenix.Auth.Mfa.RecoveryRecord do
  @moduledoc "PostgreSQL schema for one-time MFA recovery code digests."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_mfa_recovery_code" do
    field :user_id, :binary_id
    field :batch_id, :binary_id
    field :code_hash, :string
    field :used_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "只接受 64 位十六进制 HMAC 摘要。"
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:id, :user_id, :batch_id, :code_hash, :used_at])
    |> validate_required([:id, :user_id, :batch_id, :code_hash])
    |> validate_format(:code_hash, ~r/\A[0-9a-f]{64}\z/)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:code_hash, name: :sys_mfa_recovery_user_hash_unique_index)
  end
end
