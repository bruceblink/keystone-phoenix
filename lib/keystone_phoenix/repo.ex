defmodule KeystonePhoenix.Repo do
  use Ecto.Repo,
    otp_app: :keystone_phoenix,
    adapter: Ecto.Adapters.Postgres
end
