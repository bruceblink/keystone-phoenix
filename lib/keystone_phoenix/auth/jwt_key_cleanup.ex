defmodule KeystonePhoenix.Auth.JwtKeyCleanup do
  @moduledoc "周期清理已经超过保留期限的 JWT 公钥注册记录。"

  use GenServer

  require Logger

  alias KeystonePhoenix.Auth.JwtKeyRegistry

  @default_interval_ms 3_600_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval_ms, configured_interval())
    schedule(interval)
    {:ok, %{interval_ms: interval}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    case JwtKeyRegistry.retire_expired() do
      {:ok, %{retired: retired, deleted: deleted}} when retired > 0 or deleted > 0 ->
        Logger.info("JWT key registry cleanup retired=#{retired} deleted=#{deleted}")

      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.warning("JWT key registry cleanup failed: #{inspect(reason)}")
    end

    schedule(state.interval_ms)
    {:noreply, state}
  end

  defp configured_interval do
    Application.get_env(
      :keystone_phoenix,
      :jwt_key_registry_cleanup_interval_ms,
      @default_interval_ms
    )
  end

  defp schedule(interval), do: Process.send_after(self(), :cleanup, max(interval, 1_000))
end
