defmodule KeystonePhoenixWeb.AdminPages.StatusTest do
  @moduledoc "管理后台状态徽标映射的回归测试。"

  use ExUnit.Case, async: true

  alias KeystonePhoenixWeb.Live.AdminPages.Status

  test "maps ordinary, log, job log, and network states" do
    assert Status.normal_paused(1) == "status-badge--normal"
    assert Status.normal_paused(0) == "status-badge--paused"
    assert Status.success_failure(1) == "status-badge--success"
    assert Status.success_failure(0) == "status-badge--failure"
    assert Status.job_log(2) == "status-badge--skipped"
    assert Status.job_log(99) == "status-badge--unknown"
    assert Status.network("ONLINE") == "status-badge--success"
    assert Status.network("OFFLINE") == "status-badge--failure"
    assert Status.network("DEGRADED") == "status-badge--unknown"
  end
end
