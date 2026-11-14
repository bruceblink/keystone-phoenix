defmodule KeystonePhoenix.Auth.Passkey.Challenge do
  @moduledoc """
  记录并一次性消费 WebAuthn challenge。

  Ithibati 只在数据库保存 challenge 摘要；签名的 Phoenix session 保存完整 challenge
  元数据和注册账户绑定。验证前先删除 session，再消费数据库记录，避免并发重放。
  """

  def issue(%Wax.Challenge{} = challenge) do
    case Ithibati.Identity.Challenges.store(challenge) do
      :ok -> {:ok, id(challenge)}
    end
  rescue
    _ -> {:error, :passkey_unavailable}
  end

  def consume(%{bytes: bytes} = retained) when is_binary(bytes) do
    with true <- id(retained) == Base.url_encode64(bytes, padding: false),
         :ok <- Ithibati.Identity.Challenges.consume(retained) do
      :ok
    else
      _ -> {:error, :passkey_challenge_invalid}
    end
  rescue
    _ -> {:error, :passkey_unavailable}
  end

  def consume(_retained), do: {:error, :passkey_challenge_invalid}

  def id(%{bytes: bytes}) when is_binary(bytes),
    do: Base.url_encode64(bytes, padding: false)

  def id(_retained), do: nil

  def purge_expired, do: Ithibati.Identity.Challenges.delete_expired()
end
