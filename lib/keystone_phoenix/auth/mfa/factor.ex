defmodule KeystonePhoenix.Auth.Mfa.Factor do
  @moduledoc "PostgreSQL schema for an encrypted user MFA factor."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "sys_user_mfa" do
    field :user_id, :binary_id
    field :mfa_type, :string, default: "TOTP"
    field :secret_ciphertext, :binary
    field :secret_nonce, :binary
    field :key_version, :integer, default: 1
    field :enabled, :boolean, default: false
    field :enrolled_at, :utc_datetime_usec
    field :last_used_at, :utc_datetime_usec
    field :failed_attempt_count, :integer, default: 0
    field :locked_until, :utc_datetime_usec
    field :last_accepted_step, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @doc "校验待启用或已启用的 TOTP 密钥记录。"
  def changeset(factor, attrs) do
    factor
    |> cast(attrs, [
      :id,
      :user_id,
      :mfa_type,
      :secret_ciphertext,
      :secret_nonce,
      :key_version,
      :enabled,
      :enrolled_at,
      :last_used_at,
      :failed_attempt_count,
      :locked_until,
      :last_accepted_step
    ])
    |> validate_required([
      :id,
      :user_id,
      :mfa_type,
      :secret_ciphertext,
      :secret_nonce,
      :key_version
    ])
    |> validate_inclusion(:mfa_type, ["TOTP"])
    |> validate_number(:key_version, greater_than: 0)
    |> validate_nonce_length()
    |> validate_number(:failed_attempt_count, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id, name: :sys_user_mfa_user_unique_index)
  end

  defp validate_nonce_length(changeset) do
    validate_change(changeset, :secret_nonce, fn :secret_nonce, value ->
      if is_binary(value) and byte_size(value) == 12, do: [], else: [secret_nonce: "必须是 12 字节"]
    end)
  end
end
