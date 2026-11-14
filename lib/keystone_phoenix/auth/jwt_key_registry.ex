defmodule KeystonePhoenix.Auth.JwtKeyRegistry do
  @moduledoc "持久化 JWT 公钥注册表及轮换状态。"

  import Ecto.Query

  alias KeystonePhoenix.Auth.{JwtKey, Token}
  alias KeystonePhoenix.Repo

  @statuses ["active", "retiring"]

  @doc "返回当前仍可验签的 JWK Set；数据库不可用时返回运行时配置的当前公钥。"
  def public_jwk_set do
    now = DateTime.utc_now()

    with :ok <- validate_key_id(Application.get_env(:keystone_phoenix, :jwt_key_id, "keystone")) do
      publish_registered_keys(now)
    end
  rescue
    _ -> Token.runtime_public_jwk_set()
  end

  defp publish_registered_keys(now) do
    case registered_keys(now) do
      [] ->
        _ = bootstrap_from_runtime()
        registered_keys(now) |> jwk_set_or_runtime()

      keys ->
        {:ok, %{"keys" => Enum.map(keys, & &1.public_jwk)}}
    end
  end

  @doc "按 kid 查找仍在保留期内的公钥。"
  def public_jwk_for(key_id) when is_binary(key_id) do
    now = DateTime.utc_now()
    statuses = @statuses

    case Repo.one(
           from key in JwtKey,
             where: key.key_id == ^key_id and key.status in ^statuses,
             where: is_nil(key.expires_at) or key.expires_at > ^now,
             select: key.public_jwk
         ) do
      nil -> {:error, :unknown_key_id}
      jwk -> {:ok, jwk}
    end
  rescue
    _ -> {:error, :registry_unavailable}
  end

  @doc "登记一个公钥。私钥仍由运行时密钥托管，不写入数据库。"
  def register(key_id, public_jwk, opts \\ []) do
    with :ok <- validate_key_id(key_id),
         {:ok, public_jwk} <- normalize_public_jwk(public_jwk),
         {:ok, activated_at} <- option_datetime(opts, :activated_at, DateTime.utc_now()),
         {:ok, expires_at} <- option_datetime(opts, :expires_at, nil) do
      %JwtKey{}
      |> JwtKey.changeset(%{
        id: KeystonePhoenix.Identity.v7(),
        key_id: key_id,
        public_jwk: Map.merge(public_jwk, %{"kid" => key_id, "alg" => "RS256", "use" => "sig"}),
        status: Keyword.get(opts, :status, "retiring"),
        activated_at: activated_at,
        retire_at: Keyword.get(opts, :retire_at),
        expires_at: expires_at
      })
      |> Repo.insert()
    end
  end

  @doc "将指定公钥设为 active，并按宽限期将旧 active key 标为 retiring。"
  def activate(key_id, grace_seconds \\ 86_400)

  def activate(key_id, grace_seconds)
      when is_integer(grace_seconds) and grace_seconds >= 0 do
    Repo.transaction(fn ->
      now = DateTime.utc_now()
      retire_at = DateTime.add(now, grace_seconds, :second)

      from(key in JwtKey, where: key.status == "active")
      |> Repo.update_all(set: [status: "retiring", retire_at: retire_at, updated_at: now])

      case Repo.get_by(JwtKey, key_id: key_id) do
        nil ->
          Repo.rollback(:unknown_key_id)

        key ->
          key
          |> JwtKey.changeset(%{status: "active", activated_at: now, retire_at: nil})
          |> Repo.update()
          |> case do
            {:ok, value} -> value
            {:error, changeset} -> Repo.rollback(changeset)
          end
      end
    end)
  end

  def activate(_key_id, _grace_seconds), do: {:error, :invalid_grace_period}

  @doc "将到期旧 key 标为 retired，并清理超过保留期的 retired metadata。"
  def retire_expired(retention_seconds \\ 7 * 24 * 60 * 60)

  def retire_expired(retention_seconds)
      when is_integer(retention_seconds) and retention_seconds >= 0 do
    now = DateTime.utc_now()
    retention_cutoff = DateTime.add(now, -retention_seconds, :second)

    {retired, _} =
      from(key in JwtKey,
        where: key.status == "retiring" and not is_nil(key.retire_at) and key.retire_at <= ^now
      )
      |> Repo.update_all(set: [status: "retired", updated_at: now])

    {deleted, _} =
      from(key in JwtKey, where: key.status == "retired" and key.updated_at <= ^retention_cutoff)
      |> Repo.delete_all()

    {:ok, %{retired: retired, deleted: deleted}}
  end

  def retire_expired(_retention_seconds), do: {:error, :invalid_retention_period}

  defp registered_keys(now) do
    statuses = @statuses

    Repo.all(
      from key in JwtKey,
        where: key.status in ^statuses,
        where: is_nil(key.expires_at) or key.expires_at > ^now,
        order_by: [asc: key.activated_at]
    )
  end

  defp jwk_set_or_runtime([]), do: Token.runtime_public_jwk_set()
  defp jwk_set_or_runtime(keys), do: {:ok, %{"keys" => Enum.map(keys, & &1.public_jwk)}}

  defp bootstrap_from_runtime do
    with {:ok, %{"keys" => [jwk]}} <- Token.runtime_public_jwk_set(),
         [key_id] <- [Application.get_env(:keystone_phoenix, :jwt_key_id, "keystone")],
         {:ok, _} <- register(key_id, jwk, status: "active") do
      {:ok, [jwk]}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
      _ -> {:error, :bootstrap_failed}
    end
  end

  defp normalize_public_jwk(jwk) when is_map(jwk) do
    if jwk["kty"] == "RSA" and is_binary(jwk["n"]) and is_binary(jwk["e"]) do
      {:ok, Map.take(jwk, ["kty", "n", "e", "alg", "use", "kid"])}
    else
      {:error, :invalid_public_jwk}
    end
  end

  defp normalize_public_jwk(_), do: {:error, :invalid_public_jwk}

  defp validate_key_id(value) when is_binary(value) do
    if Regex.match?(~r/^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$/, value),
      do: :ok,
      else: {:error, :invalid_key_id}
  end

  defp validate_key_id(_), do: {:error, :invalid_key_id}

  defp option_datetime(opts, key, default) do
    case Keyword.get(opts, key, default) do
      nil -> {:ok, nil}
      %DateTime{} = value -> {:ok, value}
      _ -> {:error, {:invalid_datetime, key}}
    end
  end
end
