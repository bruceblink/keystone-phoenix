defmodule KeystonePhoenix.Auth.Mfa.RateLimiter do
  @moduledoc """
  对 MFA 验证失败执行主体和来源地址双维度限流。

  维度键只保存 SHA-256 摘要。数据库行锁保证多节点并发失败计数不会被覆盖；成功
  后只清理主体维度，来源地址维度保留到窗口结束，避免攻击者利用一次成功请求清空
  来源限制。
  """

  import Ecto.Query

  alias KeystonePhoenix.Auth.Mfa.RateLimit
  alias KeystonePhoenix.Repo

  @max_failures 5
  @window_seconds 60
  @block_seconds 300

  @doc "判断主体或来源地址是否仍处于阻断期。"
  def blocked?(user_id, ip_address \\ nil) do
    now = DateTime.utc_now()

    keys(user_id, ip_address)
    |> Enum.any?(fn key ->
      case Repo.get_by(RateLimit, scope_key: key) do
        %RateLimit{blocked_until: %DateTime{} = until} -> DateTime.compare(until, now) == :gt
        _ -> false
      end
    end)
  end

  @doc "原子记录主体和地址两个维度的一次失败。"
  def record_failure(user_id, ip_address \\ nil) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      Enum.each(keys(user_id, ip_address), fn key -> increment(key, now) end)
    end)
  end

  @doc "成功完成二次认证后清理主体维度。"
  def clear_user(user_id) do
    Repo.delete_all(from row in RateLimit, where: row.scope_key == ^scope_key("user", user_id))
    :ok
  end

  @doc "对输入地址只保留一个字面地址，无法解析时使用 unknown。"
  def normalize_ip(value) do
    value =
      if is_binary(value),
        do: value |> String.split(",", parts: 2) |> hd() |> String.trim(),
        else: "unknown"

    value = String.trim(value, "[]")

    if value != "" and byte_size(value) <= 64 and literal_ip?(value), do: value, else: "unknown"
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

        # 并发请求可能在第一次查询后抢先插入同一维度；冲突时重新读取并走更新路径。
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

  defp keys(user_id, ip_address) do
    [scope_key("user", user_id), scope_key("ip", normalize_ip(ip_address))]
  end

  defp scope_key(kind, value) do
    :crypto.hash(:sha256, "mfa:" <> kind <> ":" <> to_string(value))
    |> Base.encode16(case: :lower)
  end

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
