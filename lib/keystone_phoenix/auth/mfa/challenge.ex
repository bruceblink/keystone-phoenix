defmodule KeystonePhoenix.Auth.Mfa.Challenge do
  @moduledoc "短期 MFA 认证请求的 PostgreSQL schema。"

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  @purposes ~w(LOGIN STEP_UP ENROLL RECOVERY)

  schema "sys_auth_challenge" do
    field :user_id, :binary_id
    field :purpose, :string
    field :client_id, :string
    field :session_id, :binary_id
    field :context_hash, :string
    field :expires_at, :utc_datetime_usec
    field :attempt_count, :integer, default: 0
    field :consumed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "认证请求的用途必须属于统一跨项目枚举。"
  def purposes, do: @purposes

  def changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [
      :id,
      :user_id,
      :purpose,
      :client_id,
      :session_id,
      :context_hash,
      :expires_at,
      :attempt_count,
      :consumed_at
    ])
    |> validate_required([:id, :user_id, :purpose, :client_id, :expires_at])
    |> validate_inclusion(:purpose, @purposes)
    |> validate_length(:client_id, max: 128)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> validate_length(:context_hash, max: 64)
    |> foreign_key_constraint(:user_id)
  end
end
