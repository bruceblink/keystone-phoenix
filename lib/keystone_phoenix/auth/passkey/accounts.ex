defmodule KeystonePhoenix.Auth.Passkey.Accounts do
  @moduledoc "将现有系统用户映射到 WebAuthn 账户记录。"

  alias KeystonePhoenix.Auth.Passkey.Account
  alias KeystonePhoenix.Identity
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  def for_user(%SysUser{} = user) do
    case Repo.get_by(Account, user_id: user.user_id) do
      %Account{} = account -> {:ok, account}
      nil -> create_for_user(user)
    end
  rescue
    _ -> {:error, :passkey_unavailable}
  end

  def by_id(id) when is_binary(id) do
    case Repo.get(Account, id) do
      %Account{} = account -> {:ok, account}
      nil -> {:error, :invalid_credential}
    end
  end

  def by_id(_id), do: {:error, :invalid_credential}

  def local_user(%Account{user_id: user_id}), do: KeystonePhoenix.User.get_user(user_id)

  defp create_for_user(user) do
    account = %Account{id: Identity.v7()}

    case Account.changeset(account, %{user_id: user.user_id, username: user.username})
         |> Repo.insert(on_conflict: :nothing, conflict_target: :user_id) do
      {:ok, %Account{} = account} ->
        {:ok, account}

      {:error, _changeset} ->
        case Repo.get_by(Account, user_id: user.user_id) do
          %Account{} = account -> {:ok, account}
          nil -> {:error, :passkey_unavailable}
        end
    end
  end
end
