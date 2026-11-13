defmodule KeystonePhoenix.Auth.ApiKey.RateLimit do
  @moduledoc "数据库中的 API Key 失败限流维度。"

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "sys_api_key_rate_limit" do
    field :scope_key, :string
    field :window_started_at, :utc_datetime_usec
    field :attempt_count, :integer, default: 0
    field :blocked_until, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(rate_limit, attrs) do
    rate_limit
    |> cast(attrs, [:id, :scope_key, :window_started_at, :attempt_count, :blocked_until])
    |> validate_required([:id, :scope_key, :window_started_at, :attempt_count])
    |> validate_length(:scope_key, max: 64)
    |> validate_number(:attempt_count, greater_than_or_equal_to: 0)
    |> unique_constraint(:scope_key, name: :sys_api_key_rate_limit_scope_key_unique_index)
  end
end
