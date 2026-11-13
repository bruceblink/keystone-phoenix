defmodule KeystonePhoenix.Auth.Mfa.Totp do
  @moduledoc """
  RFC 6238 TOTP 的无状态实现。

  该模块只负责密钥、验证码和时间窗口计算。重复消费、失败次数和锁定状态由
  `KeystonePhoenix.Auth.Mfa` 在数据库事务中处理。这样可以让接口层和后台任务共享
  同一套验证码规则，而不会把认证状态复制到进程内存。
  """

  import Bitwise

  @secret_bytes 20
  @step_seconds 30
  @window_steps 1
  @digits 6
  @modulus 1_000_000
  @base32_alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @doc "生成 160 位随机密钥，并返回无填充的 Base32 文本。"
  @spec generate_secret() :: String.t()
  def generate_secret do
    :crypto.strong_rand_bytes(@secret_bytes) |> encode_base32()
  end

  @doc "按 Unix 秒计算六位验证码。"
  @spec code(String.t(), integer()) :: String.t()
  def code(secret, epoch_seconds) when is_integer(epoch_seconds) and epoch_seconds >= 0 do
    secret
    |> decode_secret()
    |> totp_code(counter(epoch_seconds))
  end

  def code(_secret, _epoch_seconds),
    do: raise(ArgumentError, "epoch_seconds must be non-negative")

  @doc "在前一个、当前和后一个时间步内验证，并返回命中的时间步。"
  @spec matching_step(String.t(), term(), integer()) :: {:ok, non_neg_integer()} | :error
  def matching_step(secret, presented, epoch_seconds)
      when is_integer(epoch_seconds) and epoch_seconds >= 0 do
    secret = decode_secret(secret)
    expected_code = normalize_code(presented)
    current_step = counter(epoch_seconds)

    Enum.reduce(-@window_steps..@window_steps, nil, fn offset, matched ->
      candidate_step = current_step + offset

      if candidate_step >= 0 do
        candidate = totp_code(secret, candidate_step)
        equal = secure_compare(candidate, expected_code)

        if equal, do: {:ok, candidate_step}, else: matched
      else
        matched
      end
    end) || :error
  end

  def matching_step(_secret, _presented, _epoch_seconds), do: :error

  @doc "返回当前时间下的验证码是否正确。"
  def verify?(secret, presented, epoch_seconds \\ System.system_time(:second)) do
    matching_step(secret, presented, epoch_seconds) != :error
  end

  @doc "返回配置到认证器应用的 otpauth URI。"
  def otpauth_uri(username, secret, issuer \\ "Keystone") do
    issuer =
      if is_binary(issuer) and String.trim(issuer) != "",
        do: String.trim(issuer),
        else: "Keystone"

    username =
      if is_binary(username) and String.trim(username) != "",
        do: String.trim(username),
        else: "user"

    label = URI.encode(issuer <> ":" <> username)

    query =
      URI.encode_query(%{
        secret: secret,
        issuer: issuer,
        algorithm: "SHA1",
        digits: "6",
        period: "30"
      })

    "otpauth://totp/" <> label <> "?" <> query
  end

  @doc "公开给测试和迁移检查的验证码参数。"
  def step_seconds, do: @step_seconds
  def digits, do: @digits

  defp counter(epoch_seconds), do: div(epoch_seconds, @step_seconds)

  defp totp_code(secret, step) do
    digest = :crypto.mac(:hmac, :sha, secret, <<step::unsigned-big-64>>)
    last = :binary.last(digest)
    offset = band(last, 0x0F)
    <<value::unsigned-big-32>> = binary_part(digest, offset, 4)
    # RFC 6238 只清除最高位，保留其余 31 位参与模运算。
    value = band(value, 0x7FFFFFFF) |> rem(@modulus)
    value |> Integer.to_string() |> String.pad_leading(@digits, "0")
  end

  defp normalize_code(value) when is_binary(value) do
    value = String.trim(value)
    if Regex.match?(~r/^\d{#{@digits}}$/, value), do: value, else: "!invalid!"
  end

  defp normalize_code(_value), do: "!invalid!"

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {first, second}, result -> bor(result, bxor(first, second)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false

  defp decode_secret(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.upcase()
    normalized = String.trim_trailing(normalized, "=")

    if normalized == "" or rem(String.length(normalized), 8) in [1, 3, 6] do
      raise ArgumentError, "invalid Base32 TOTP secret"
    end

    {decoded, buffer, bits} =
      normalized
      |> String.to_charlist()
      |> Enum.reduce({<<>>, 0, 0}, fn char, {result, buffer, bits} ->
        value = base32_value(char)
        if value < 0, do: raise(ArgumentError, "invalid Base32 TOTP secret")

        buffer = bor(buffer <<< 5, value)
        bits = bits + 5

        if bits >= 8 do
          bits = bits - 8
          <<byte>> = <<buffer >>> bits>>
          {result <> <<byte>>, band(buffer, (1 <<< bits) - 1), bits}
        else
          {result, buffer, bits}
        end
      end)

    if bits > 0 and buffer != 0, do: raise(ArgumentError, "invalid Base32 trailing bits")

    if byte_size(decoded) < 16,
      do: raise(ArgumentError, "TOTP secret must contain at least 128 bits")

    decoded
  end

  defp decode_secret(_value), do: raise(ArgumentError, "TOTP secret is required")

  defp base32_value(char) when char in ?A..?Z, do: char - ?A
  defp base32_value(char) when char in ?2..?7, do: char - ?2 + 26
  defp base32_value(_char), do: -1

  defp encode_base32(bytes) do
    {result, buffer, bits} =
      bytes
      |> :binary.bin_to_list()
      |> Enum.reduce({[], 0, 0}, fn byte, {result, buffer, bits} ->
        buffer = bor(buffer <<< 8, byte)
        bits = bits + 8

        {result, buffer, bits} =
          Enum.reduce_while(Stream.iterate(0, &(&1 + 1)), {result, buffer, bits}, fn _, acc ->
            {result, buffer, bits} = acc

            if bits >= 5 do
              bits = bits - 5
              symbol = Enum.at(@base32_alphabet, band(buffer >>> bits, 0x1F))
              {:cont, {[symbol | result], band(buffer, (1 <<< bits) - 1), bits}}
            else
              {:halt, acc}
            end
          end)

        {result, buffer, bits}
      end)

    result =
      if bits > 0,
        do: [Enum.at(@base32_alphabet, band(buffer <<< (5 - bits), 0x1F)) | result],
        else: result

    result |> Enum.reverse() |> to_string()
  end
end
