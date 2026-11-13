defmodule KeystonePhoenix.Auth.Mfa.RecoveryCode do
  @moduledoc """
  一次性恢复码的生成和哈希。

  数据库只保存部署级 pepper 参与计算的 HMAC-SHA-256 摘要。明文恢复码只在生成
  批次的返回值中出现一次，调用方不能把它写入日志或安全事件。
  """

  import Bitwise

  @count 10
  @bytes 16
  @hex_length @bytes * 2

  @doc "生成十个唯一的 128 位恢复码。"
  def generate_batch do
    codes =
      Stream.repeatedly(fn ->
        :crypto.strong_rand_bytes(@bytes) |> Base.encode16(case: :upper) |> format_code()
      end)
      |> Enum.reduce_while(MapSet.new(), fn code, seen ->
        seen = MapSet.put(seen, code)
        if MapSet.size(seen) == @count, do: {:halt, seen}, else: {:cont, seen}
      end)

    %{batch_id: KeystonePhoenix.Identity.v7(), codes: MapSet.to_list(codes)}
  end

  @doc "使用配置的恢复码 pepper 计算十六进制 HMAC 摘要。"
  def hash(code, pepper \\ configured_pepper()) do
    normalized = normalize(code)
    pepper = require_pepper(pepper)
    :crypto.mac(:hmac, :sha256, pepper, normalized) |> Base.encode16(case: :lower)
  end

  @doc "校验恢复码格式，并以常量时间比较摘要。"
  def valid?(code), do: normalize(code) != :error

  def matches?(code, expected_hash, pepper \\ configured_pepper()) do
    with normalized when is_binary(normalized) <- normalize(code),
         true <- is_binary(expected_hash),
         {:ok, expected} <- Base.decode16(expected_hash, case: :mixed) do
      actual = :crypto.mac(:hmac, :sha256, require_pepper(pepper), normalized)
      secure_compare(actual, expected)
    else
      _ -> false
    end
  end

  @doc "统一恢复码文本格式，接受无分隔符或八组四位十六进制。"
  def normalize(code) when is_binary(code) do
    value = String.trim(code) |> String.upcase()

    raw =
      cond do
        Regex.match?(~r/^[0-9A-F]{#{@hex_length}}$/, value) ->
          value

        Regex.match?(~r/^[0-9A-F]{4}(?:-[0-9A-F]{4}){7}$/, value) ->
          String.replace(value, "-", "")

        true ->
          nil
      end

    if is_binary(raw), do: format_code(raw), else: :error
  end

  def normalize(_code), do: :error

  def count, do: @count

  defp configured_pepper do
    Application.get_env(:keystone_phoenix, :mfa_recovery_pepper)
  end

  defp require_pepper(pepper) when is_binary(pepper) and byte_size(pepper) >= 16, do: pepper
  defp require_pepper(_pepper), do: raise(ArgumentError, "MFA recovery pepper is not configured")

  defp format_code(raw) when byte_size(raw) == @hex_length do
    raw
    |> String.to_charlist()
    |> Enum.chunk_every(4)
    |> Enum.map(&to_string/1)
    |> Enum.join("-")
  end

  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    left
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(right))
    |> Enum.reduce(0, fn {first, second}, result -> bor(result, bxor(first, second)) end)
    |> Kernel.==(0)
  end

  defp secure_compare(_left, _right), do: false
end
