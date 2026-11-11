defmodule KeystonePhoenix.Job.SchedulerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias KeystonePhoenix.Job.Scheduler

  test "prunes trigger timestamps for disabled or deleted jobs" do
    state = %{last_trigger: %{1 => 10, 2 => 20, 3 => 30}, running: %{}}
    jobs = [%{job_id: 1}, %{job_id: 3}]

    assert %{last_trigger: %{1 => 10, 3 => 30}} = Scheduler.prune_last_triggers(state, jobs)
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
      running: %{1 => %{pid => %{ref: ref, termination: nil}}}
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
