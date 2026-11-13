defmodule KeystonePhoenix.Auth.RefreshTokenEvent do
  @moduledoc "Refresh token state transition audit record."

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "auth_refresh_token_events" do
    field :token_id, :binary_id
    field :user_id, :binary_id
    field :refresh_family_id, :binary_id
    field :event_type, :string
    field :client_id, :string
    field :detail, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
