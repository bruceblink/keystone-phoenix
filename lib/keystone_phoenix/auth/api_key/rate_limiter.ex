defmodule KeystonePhoenix.Auth.ApiKey.RateLimiter do
  @moduledoc """
  API Key 认证失败的数据库限流器。

  数据库只保存来源地址和凭据摘要两个维度。成功认证只清理当前凭据维度，来源地址
  维度继续保留，避免一个有效凭据清空该来源的其他失败记录。
  """

  import Ecto.Query

  alias KeystonePhoenix.Auth.ApiKey.RateLimit
  alias KeystonePhoenix.Repo

  @max_failures 20
  @window_seconds 60
  @block_seconds 300

  @doc "判断来源地址或凭据摘要是否处于阻断期。"
  def blocked?(value, ip_address \\ nil) do
    now = DateTime.utc_now()

    keys(value, ip_address)
    |> Enum.any?(fn key ->
      case Repo.get_by(RateLimit, scope_key: key) do
        %RateLimit{blocked_until: %DateTime{} = until} -> DateTime.compare(until, now) == :gt
        _ -> false
      end
    end)
  end

  @doc "原子增加来源地址和凭据两个维度的失败次数。"
  def record_failure(value, ip_address \\ nil) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      Enum.each(keys(value, ip_address), &increment(&1, now))
    end)
  end

  @doc "成功认证后只清理当前凭据维度。"
  def clear(value) do
    key = scope_key("key", hash(value))
    Repo.delete_all(from row in RateLimit, where: row.scope_key == ^key)
    :ok
  end

  @doc "来源地址只接受一个字面地址；无法识别时使用 unknown。"
  def normalize_ip(value) do
    value =
      if is_binary(value),
        do: value |> String.split(",", parts: 2) |> hd() |> String.trim(),
        else: "unknown"

    value = String.trim(value, "[]")

    if value != "" and byte_size(value) <= 64 and literal_ip?(value), do: value, else: "unknown"
  end

  @doc "返回限流维度键，键本身不会暴露明文 API Key。"
  def keys(value, ip_address) do
    [scope_key("ip", normalize_ip(ip_address)), scope_key("key", hash(value))]
  end

  defp increment(key, now) do
    row = Repo.one(from entry in RateLimit, where: entry.scope_key == ^key, lock: "FOR UPDATE")

    case row do
      nil ->
        blocked_until = if @max_failures <= 1, do: DateTime.add(now, @block_seconds, :second)

        {inserted, _} =
          Repo.insert_all(
            RateLimit,
            [
              %{
                id: KeystonePhoenix.Identity.v7(),
                scope_key: key,
                window_started_at: now,
                attempt_count: 1,
                blocked_until: blocked_until,
                inserted_at: now,
                updated_at: now
              }
            ],
            on_conflict: :nothing,
            conflict_target: [:scope_key]
          )

        # 两个请求可能在首次读取后同时创建维度，冲突时重新读取锁定行。
        if inserted == 0, do: increment(key, now)

      row ->
        {window_started_at, attempts} =
          if DateTime.compare(DateTime.add(row.window_started_at, @window_seconds, :second), now) ==
               :gt,
             do: {row.window_started_at, row.attempt_count + 1},
             else: {now, 1}

        blocked_until =
          if attempts >= @max_failures, do: DateTime.add(now, @block_seconds, :second)

        Repo.update!(
          Ecto.Changeset.change(row,
            window_started_at: window_started_at,
            attempt_count: attempts,
            blocked_until: blocked_until
          )
        )
    end
  end

  defp scope_key(kind, value),
    do: :crypto.hash(:sha256, "api-key:" <> kind <> ":" <> value) |> Base.encode16(case: :lower)

  defp hash(value) when is_binary(value),
    do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp hash(_value), do: :crypto.hash(:sha256, "") |> Base.encode16(case: :lower)

  defp literal_ip?(value) do
    ipv4? =
      case String.split(value, ".") do
        parts when length(parts) == 4 -> Enum.all?(parts, &valid_ipv4_part?/1)
        _ -> false
      end

    ipv4? or (String.contains?(value, ":") and Regex.match?(~r/^[0-9A-Fa-f:]+$/, value))
  end

  defp valid_ipv4_part?(part) do
    case Integer.parse(part) do
      {value, ""} when value in 0..255 -> true
      _ -> false
    end
  end
end
