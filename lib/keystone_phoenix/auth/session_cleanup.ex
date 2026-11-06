defmodule KeystonePhoenix.Auth.SessionCleanup do
  @moduledoc "Periodic cleanup of expired PostgreSQL-backed authentication sessions."

  use GenServer

  alias KeystonePhoenix.Auth.Session

  @default_interval_ms 60_000

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
    _ = Session.cleanup_expired()
    schedule(state.interval_ms)
    {:noreply, state}
  end

  defp configured_interval do
    Application.get_env(
      :keystone_phoenix,
      :auth_session_cleanup_interval_ms,
      @default_interval_ms
    )
  end

  defp schedule(interval), do: Process.send_after(self(), :cleanup, max(interval, 1_000))
end
