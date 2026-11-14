defmodule KeystonePhoenix.Job.SchedulerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias KeystonePhoenix.Job.Scheduler

  test "automatic polling requires the explicit scheduler permissions and all scope" do
    assert {:error, :permission_denied} =
             Scheduler.enabled_jobs(
               authorization: %{principal: %{data_scope: "ALL", permissions: ["job:read"]}}
             )

    assert {:error, :data_scope_denied} =
             Scheduler.enabled_jobs(
               authorization: %{
                 principal: %{
                   data_scope: "OWNER",
                   subject_id: "018f2a7e-5d3c-7b01-8a11-000000000110",
                   permissions: ["job:read", "job:run"]
                 }
               }
             )

    assert [authorization: authorization] = KeystonePhoenix.Job.Authorization.system_options()
    assert :scheduler = authorization[:source]
    assert %{data_scope: "ALL", permissions: permissions} = authorization[:principal]
    assert Enum.sort(permissions) == ["job:read", "job:run"]
  end

  test "prunes trigger timestamps for disabled or deleted jobs" do
    first_id = "018f2a7e-5d3c-7b01-8a11-000000000111"
    second_id = "018f2a7e-5d3c-7b01-8a11-000000000112"
    third_id = "018f2a7e-5d3c-7b01-8a11-000000000113"
    state = %{last_trigger: %{first_id => 10, second_id => 20, third_id => 30}, running: %{}}
    jobs = [%{job_id: first_id}, %{job_id: third_id}]

    assert %{last_trigger: %{^first_id => 10, ^third_id => 30}} =
             Scheduler.prune_last_triggers(state, jobs)
  end

  test "only scheduler-marked cancellation and timeout kills are expected" do
    assert Scheduler.expected_kill?(:cancelled, :killed)
    assert Scheduler.expected_kill?({:timeout, 1_000}, :killed)

    refute Scheduler.expected_kill?(nil, :killed)
    refute Scheduler.expected_kill?(:cancelled, :normal)
    refute Scheduler.expected_kill?({:timeout, 1_000}, :shutdown)
  end

  # 未标记的 :killed 退出仍需保留 warning，便于发现异常终止。
  test "warns for an unexpected killed task exit" do
    pid = self()
    ref = make_ref()

    state = %{
      last_trigger: %{},
      running: %{
        "018f2a7e-5d3c-7b01-8a11-000000000114" => %{pid => %{ref: ref, termination: nil}}
      }
    }

    log =
      capture_log(fn ->
        assert {:noreply, %{running: %{}}} =
                 Scheduler.handle_info({:DOWN, ref, :process, pid, :killed}, state)
      end)

    assert log =~ "scheduled job task"
    assert log =~ "stopped: :killed"
  end
end
