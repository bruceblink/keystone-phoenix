defmodule KeystonePhoenix.Auth.Mfa.ChallengeCleanup do
  @moduledoc "周期分批清理已过期的 PostgreSQL MFA 认证请求。"

  use GenServer

  import Ecto.Query

  require Logger

  alias KeystonePhoenix.Auth.Mfa.Challenge
  alias KeystonePhoenix.Repo

  @default_interval_ms 60_000
  @default_batch_size 500
  @default_issue_window_seconds 60
  @max_batch_size 10_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "在一个事务中删除至多一批已过期请求，并保留仍占签发额度的 STEP_UP 请求。"
  def cleanup_expired_batch(now, issue_window_seconds, batch_size)
      when is_struct(now, DateTime) and is_integer(issue_window_seconds) and
             issue_window_seconds > 0 and is_integer(batch_size) and
             batch_size in 1..@max_batch_size do
    cutoff = DateTime.add(now, -issue_window_seconds, :second)

    Repo.transaction(fn ->
      ids =
        from(challenge in Challenge,
          where:
            challenge.expires_at <= ^now and
              (challenge.purpose != "STEP_UP" or challenge.inserted_at <= ^cutoff),
          order_by: [asc: challenge.expires_at, asc: challenge.id],
          limit: ^batch_size,
          select: challenge.id,
          lock: "FOR UPDATE SKIP LOCKED"
        )
        |> Repo.all()

      case ids do
        [] ->
          0

        _ ->
          {deleted, _} = Repo.delete_all(from challenge in Challenge, where: challenge.id in ^ids)
          deleted
      end
    end)
  end

  def cleanup_expired_batch(_now, _issue_window_seconds, _batch_size),
    do: {:error, :invalid_cleanup_configuration}

  @impl true
  def init(opts) do
    interval_ms =
      Keyword.get(
        opts,
        :interval_ms,
        configured(:mfa_challenge_cleanup_interval_ms, @default_interval_ms)
      )

    batch_size = configured(:mfa_challenge_cleanup_batch_size, @default_batch_size)

    issue_window_seconds =
      configured(:mfa_step_up_issue_window_seconds, @default_issue_window_seconds)

    validate_configuration!(interval_ms, batch_size, issue_window_seconds)
    schedule(interval_ms)

    {:ok,
     %{
       interval_ms: interval_ms,
       batch_size: batch_size,
       issue_window_seconds: issue_window_seconds
     }}
  end

  @impl true
  def handle_info(:cleanup, state) do
    case cleanup_expired_batch(DateTime.utc_now(), state.issue_window_seconds, state.batch_size) do
      {:ok, deleted} when deleted > 0 ->
        Logger.info("MFA challenge cleanup deleted=#{deleted}")

      {:ok, _deleted} ->
        :ok

      {:error, reason} ->
        Logger.warning("MFA challenge cleanup failed: #{inspect(reason)}")
    end

    schedule(state.interval_ms)
    {:noreply, state}
  end

  defp configured(key, default), do: Application.get_env(:keystone_phoenix, key, default)

  defp validate_configuration!(interval_ms, batch_size, issue_window_seconds) do
    if is_integer(interval_ms) and interval_ms >= 1_000 and
         is_integer(batch_size) and batch_size in 1..@max_batch_size and
         is_integer(issue_window_seconds) and issue_window_seconds > 0 do
      :ok
    else
      raise ArgumentError, "MFA challenge cleanup configuration is invalid"
    end
  end

  defp schedule(interval_ms), do: Process.send_after(self(), :cleanup, interval_ms)
end
