defmodule KeystonePhoenix.Job.SchedulerTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Job.Scheduler

  test "prunes trigger timestamps for disabled or deleted jobs" do
    state = %{last_trigger: %{1 => 10, 2 => 20, 3 => 30}, running: %{}}
    jobs = [%{job_id: 1}, %{job_id: 3}]

    assert %{last_trigger: %{1 => 10, 3 => 30}} = Scheduler.prune_last_triggers(state, jobs)
  end
end
