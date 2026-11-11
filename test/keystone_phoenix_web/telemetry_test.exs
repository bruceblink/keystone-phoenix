defmodule KeystonePhoenixWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Telemetry

  test "exposes runtime and job metrics" do
    metric_names = Enum.map(Telemetry.metrics(), &Enum.join(&1.name, "."))

    assert "keystone_phoenix.runtime.cache_entries" in metric_names
    assert "keystone_phoenix.runtime.captcha_entries" in metric_names
    assert "keystone_phoenix.runtime.auth_sessions" in metric_names
    assert "keystone_phoenix.repo.pool.ready_connections" in metric_names
    assert "keystone_phoenix.repo.pool.checkout_queue_length" in metric_names
    assert "keystone_phoenix.repo.pool.pool_size" in metric_names
    assert "keystone_phoenix.repo.pool.pool_count" in metric_names
    assert "keystone_phoenix.job.run.duration" in metric_names
    assert function_exported?(Telemetry, :measure_runtime, 0)
    assert function_exported?(Telemetry, :measure_repo_pool, 0)
  end

  test "measures the repository pool without affecting the caller" do
    assert :ok = Telemetry.measure_repo_pool()
  end

  test "emits non-negative repository pool gauges" do
    event = [:keystone_phoenix, :repo, :pool]
    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler_id,
      event,
      fn ^event, measurements, _metadata, pid ->
        send(pid, {:repo_pool_measurements, measurements})
      end,
      self()
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    assert :ok = Telemetry.measure_repo_pool()
    assert_receive {:repo_pool_measurements, measurements}
    assert measurements.ready_connections >= 0
    assert measurements.checkout_queue_length >= 0
    assert measurements.pool_size >= 0
    assert measurements.pool_count >= 1
  end
end
