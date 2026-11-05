defmodule KeystonePhoenix.RuntimeStore do
  @moduledoc "Application-owned ETS tables for rebuildable runtime data."

  use GenServer

  @cache_table :keystone_phoenix_cache
  @captcha_table :keystone_phoenix_captcha
  @sweep_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def cache_table, do: @cache_table
  def captcha_table, do: @captcha_table

  @impl true
  def init(_opts) do
    create_table(@cache_table)
    create_table(@captcha_table)
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    expires_at = System.monotonic_time(:millisecond)
    sweep_table(@cache_table, expires_at)
    sweep_table(@captcha_table, expires_at)
    schedule_sweep()
    {:noreply, state}
  end

  defp create_table(table) do
    if :ets.whereis(table) == :undefined do
      :ets.new(table, [
        :named_table,
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])
    end
  end

  defp sweep_table(table, expires_at) do
    if :ets.whereis(table) != :undefined do
      :ets.select_delete(table, [{{:"$1", :"$2", :"$3"}, [{:<, :"$3", expires_at}], [true]}])
    end
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_interval_ms)
end
