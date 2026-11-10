defmodule KeystonePhoenix.HealthTest do
  use KeystonePhoenix.DataCase, async: false

  alias KeystonePhoenix.Health

  test "readiness reports database and ETS dependencies" do
    readiness = Health.readiness()

    assert readiness["status"] == "READY"
    assert readiness["database"] == "UP"
    assert readiness["cache"] == "UP"
  end
end
