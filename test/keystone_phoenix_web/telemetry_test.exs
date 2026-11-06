defmodule KeystonePhoenixWeb.TelemetryTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Telemetry

  test "exposes runtime and job metrics" do
    metric_names = Enum.map(Telemetry.metrics(), &Enum.join(&1.name, "."))

    assert "keystone_phoenix.runtime.cache_entries" in metric_names
    assert "keystone_phoenix.runtime.captcha_entries" in metric_names
    assert "keystone_phoenix.runtime.auth_sessions" in metric_names
    assert "keystone_phoenix.job.run.duration" in metric_names
    assert function_exported?(Telemetry, :measure_runtime, 0)
  end
end
