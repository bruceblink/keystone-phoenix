defmodule KeystonePhoenix.Auth.Oidc.Identity do
  @moduledoc "将 OIDC issuer 和 subject 映射到本地用户。"

  import Ecto.Query

  alias KeystonePhoenix.Auth.Oidc.Config
  alias KeystonePhoenix.Repo
  alias KeystonePhoenix.User.SysUser

  def resolve(claims, config) when is_map(claims) and is_map(config) do
    provider = provider_key(config[:issuer])
    subject = claims["sub"]
    external_key = provider <> ":" <> subject

    if valid_external_key?(external_key) do
      case Repo.one(
             from user in SysUser,
               where: user.external_subject == ^external_key and user.deleted == false
           ) do
        %SysUser{} = user -> {:ok, user}
        nil -> maybe_provision(claims, config, external_key, provider)
      end
    else
      {:error, :invalid_external_identity}
    end
  rescue
    _ -> {:error, :authorization_unavailable}
  end

  defp maybe_provision(claims, config, external_key, provider) do
    if not Config.auto_provision?(config) do
      {:error, :external_identity_unmapped}
    else
      provision(claims, external_key, provider)
    end
  end

  defp provision(claims, external_key, provider) do
    username = provisioned_username(claims)
    password = Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false) <> "Aa1!"

    Repo.transaction(fn ->
      %SysUser{}
      |> SysUser.create_changeset(%{username: username, password: password, status: 1})
      |> Ecto.Changeset.put_change(:external_subject, external_key)
      |> Ecto.Changeset.put_change(:external_user_id, provider)
      |> Repo.insert()
      |> case do
        {:ok, user} -> user
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, _} -> {:error, :external_identity_unmapped}
    end
  end

  defp provider_key(issuer) do
    issuer
    |> String.trim()
    |> String.trim_trailing("/")
  end

  defp provisioned_username(claims) do
    candidate =
      claims["preferred_username"] || claims["email"] ||
        "oidc_" <> String.slice(claims["sub"], 0, 16)

    candidate = Regex.replace(~r/[^A-Za-z0-9_]/, to_string(candidate), "_")

    candidate =
      if Regex.match?(~r/^[A-Za-z_]/, candidate), do: candidate, else: "oidc_" <> candidate

    String.slice(candidate, 0, 64)
  end

  defp valid_external_key?(value), do: byte_size(value) <= 512 and String.valid?(value)
end
