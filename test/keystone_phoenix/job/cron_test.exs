defmodule KeystonePhoenix.Job.CronTest do
  use ExUnit.Case, async: true

  alias KeystonePhoenix.Job.Cron

  test "validates six-field expressions and rejects malformed fields" do
    assert :ok = Cron.validate("*/5 * * * * *")
    assert :ok = Cron.validate("0 0/10 8-18 * * 1-5")
    assert {:error, :expected_six_fields} = Cron.validate("0 0 * * *")
    assert {:error, :out_of_range} = Cron.validate("61 * * * * *")
  end

  test "matches seconds, minutes, hours, and standard Sunday-based weekdays" do
    monday = ~U[2026-11-02 08:05:10Z]
    sunday = ~U[2026-11-08 08:05:10Z]

    assert Cron.matches?("10 5 8 * * 1-5", monday)
    refute Cron.matches?("11 5 8 * * 1-5", monday)
    assert Cron.matches?("10 5 8 * * 0,7", sunday)
    refute Cron.matches?("10 5 8 * * 1-5", sunday)
  end
end
