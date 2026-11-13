defmodule KeystonePhoenix.Auth.Mfa.SecretCipher do
  @moduledoc "使用部署级 AES-256-GCM 密钥保护 TOTP 密钥。"

  @nonce_bytes 12
  @tag_bytes 16

  @doc "返回当前密钥版本。密钥来自运行时配置，不写入仓库。"
  def current_key_version do
    Application.get_env(:keystone_phoenix, :mfa_master_key_version, 1)
  end

  @doc "加密密钥，并把用户、记录和版本绑定到 AAD。"
  def encrypt(user_id, factor_id, secret, key_version \\ current_key_version()) do
    key = master_key!()
    nonce = :crypto.strong_rand_bytes(@nonce_bytes)
    aad = aad(user_id, factor_id, key_version)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, nonce, secret, aad, true)
    %{ciphertext: ciphertext <> tag, nonce: nonce, key_version: key_version}
  rescue
    error in [ArgumentError, RuntimeError] -> reraise(error, __STACKTRACE__)
  end

  @doc "校验密钥版本和认证标签后解密 TOTP 密钥。"
  def decrypt(user_id, factor_id, %{
        ciphertext: ciphertext,
        nonce: nonce,
        key_version: key_version
      })
      when is_binary(ciphertext) and is_binary(nonce) do
    key = master_key!()

    if key_version != current_key_version(),
      do: raise(ArgumentError, "MFA master key version is unavailable")

    if byte_size(ciphertext) <= @tag_bytes or byte_size(nonce) != @nonce_bytes,
      do: raise(ArgumentError, "invalid encrypted MFA secret")

    {encrypted, tag} = :erlang.split_binary(ciphertext, byte_size(ciphertext) - @tag_bytes)

    case :crypto.crypto_one_time_aead(
           :aes_256_gcm,
           key,
           nonce,
           encrypted,
           aad(user_id, factor_id, key_version),
           tag,
           false
         ) do
      plaintext when is_binary(plaintext) -> plaintext
      _ -> raise ArgumentError, "MFA secret cannot be decrypted"
    end
  rescue
    _error -> raise ArgumentError, "MFA secret cannot be decrypted"
  end

  def decrypt(_user_id, _factor_id, _value),
    do: raise(ArgumentError, "invalid encrypted MFA secret")

  defp master_key! do
    value = Application.get_env(:keystone_phoenix, :mfa_master_key)

    cond do
      is_binary(value) and byte_size(value) == 32 ->
        value

      is_binary(value) ->
        case Base.decode64(value) do
          {:ok, key} when byte_size(key) == 32 -> key
          _ -> raise ArgumentError, "MFA master key must be 32 bytes or Base64 encoded"
        end

      true ->
        raise ArgumentError, "MFA master key is not configured"
    end
  end

  defp aad(user_id, factor_id, key_version) do
    KeystonePhoenix.Identity.canonical!(user_id) <>
      ":" <>
      KeystonePhoenix.Identity.canonical!(factor_id) <> ":" <> Integer.to_string(key_version)
  end
end
