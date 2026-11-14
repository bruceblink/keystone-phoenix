defmodule KeystonePhoenix.Auth.Passkey.Account do
  @moduledoc """
  WebAuthn 账户映射。每个本地用户最多对应一条 passkey 账户记录。

  Ithibati 只管理凭据和验证流程；本地用户、权限和令牌仍由 Keystone Phoenix 管理。
  """

  use Ecto.Schema

  alias Ithibati.Schema.{Identifier, User}

  use User, identifier: :username, format: Identifier.username_format()

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "auth_passkey_accounts" do
    ithibati_account()

    field :user_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(account, attrs) do
    account
    |> identifier_changeset(attrs)
    |> Ecto.Changeset.cast(attrs, [:user_id])
    |> Ecto.Changeset.validate_required([:user_id])
    |> Ecto.Changeset.unique_constraint(:user_id, name: :auth_passkey_accounts_user_id_unique)
  end

  def passkey_display_name(account), do: account.username
end
