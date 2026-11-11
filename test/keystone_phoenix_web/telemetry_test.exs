defmodule KeystonePhoenixWeb.TelemetryTest do
  use ExUnit.Case, async: false

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
    assert "keystone_phoenix.repo.pool.alert.count" in metric_names
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

  test "emits a structured alert when the queue reaches the threshold" do
    previous = Application.get_env(:keystone_phoenix, :repo_pool_queue_alert_threshold)
    Application.put_env(:keystone_phoenix, :repo_pool_queue_alert_threshold, 0)

    event = [:keystone_phoenix, :repo, :pool, :alert]
    handler_id = {__MODULE__, make_ref()}

    :telemetry.attach(
      handler_id,
      event,
      fn ^event, measurements, metadata, pid ->
        send(pid, {:repo_pool_alert, measurements, metadata})
      end,
      self()
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
      Application.put_env(:keystone_phoenix, :repo_pool_queue_alert_threshold, previous)
    end)

    assert :ok = Telemetry.measure_repo_pool()
    assert_receive {:repo_pool_alert, %{count: 1, checkout_queue_length: queue}, metadata}
    assert queue >= 0
    assert metadata.reason == :checkout_queue
    assert metadata.threshold == 0
  end
end
